//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
#if !canImport(ObjectiveC)
import CoreFoundation // only necessary on non-Apple platforms
#endif
import CornucopiaCore
import Foundation

fileprivate let logger = Cornucopia.Core.Logger()

/// The delegate protocol. Used to communicate extraordinary conditions that (might) need special handling.
public protocol _StreamCommandQueueDelegate: AnyObject {

    func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, inputStreamReady stream: InputStream)
    func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, outputStreamReady stream: OutputStream)
    func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, didReceiveUnsolicitedData data: Data)
    func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, unexpectedEvent event: Stream.Event, on stream: Stream)
}

/// Represents a single command to be sent over the stream
private final class StreamCommand {

    typealias Continuation = CheckedContinuation<String, Error>
    
    private enum State {
        case created
        case transmitting
        case transmitted
        case responding
        case completed
        case failed
    }

    private var outputBuffer: [UInt8] = []
    private var inputBuffer: [UInt8] = []
    private var tempBuffer: [UInt8] = .init(repeating: 0, count: 8192)
    private var state: State = .created
    private let continuation: Continuation
    var timestamp: CFTimeInterval?
    var request: String
    let termination: [UInt8]
    let timeout: TimeInterval
    let timeoutHandler: () -> Void
    weak var timer: Timer?

    var canWrite: Bool { self.state == .created || self.state == .transmitting }
    var canRead: Bool { self.state == .transmitted || self.state == .responding }
    var isCompleted: Bool { self.state == .completed }

    public init(string: String, timeout: TimeInterval, termination: String, continuation: Continuation, timeoutHandler: @escaping( () -> Void)) {
        self.request = string
        self.outputBuffer = Array(string.utf8)
        self.termination = Array(termination.utf8)
        self.timeout = timeout
        self.timeoutHandler = timeoutHandler
        self.continuation = continuation
    }

    func write(to stream: OutputStream) {
        precondition(self.canWrite)
        self.state = .transmitting

        let written = stream.write(&outputBuffer, maxLength: outputBuffer.count)
        outputBuffer.removeFirst(written)
        logger.trace("wrote \(written) bytes")
        if outputBuffer.isEmpty {
            self.state = .transmitted
            self.timestamp = CFAbsoluteTimeGetCurrent()
            let timer = Timer.init(fire: Date() + self.timeout, interval: 0, repeats: false) { _ in
                self.timeoutHandler()
            }
            RunLoop.current.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func read(from stream: InputStream) {
        precondition(self.canRead)
        self.state = .responding

        let read = stream.read(&self.tempBuffer, maxLength: self.tempBuffer.count)
        logger.trace("read \(read) bytes: \(self.tempBuffer[..<read])")
        #if false //!TRUST_ALL_INPUTS
        // Some adapters insert spurious 0 bytes into the stream, hence we need a additional clearance
        self.tempBuffer.forEach {
            if $0.CC_isASCII {
                self.inputBuffer.append($0)
            }
        }
        #else
        self.inputBuffer += self.tempBuffer[0..<read]
        #endif
        guard let terminationRange = self.inputBuffer.lastRange(of: self.termination) else {
            logger.trace("did not find termination")
            return
        }
        logger.trace("got termination at \(terminationRange)")
        self.timer?.invalidate()
        self.timer = nil
        self.inputBuffer.removeLast(terminationRange.count)
        self.state = .completed
    }

    func resumeContinuation(throwing error: StreamCommandQueue.Error? = nil) {

        if let error = error {
            self.state = .failed
            self.continuation.resume(throwing: error)
            return
        }
        guard let response = String(bytes: self.inputBuffer, encoding: .utf8) else {
            self.continuation.resume(throwing: StreamCommandQueue.Error.invalidEncoding)
            return
        }
        let duration = String(format: "%04.0f ms", 1000 * (CFAbsoluteTimeGetCurrent() - self.timestamp!))
        logger.debug("Command processed [\(duration)]: '\(self.request.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n"))' => '\(response.replacingOccurrences(of: "\r", with: "\\r").replacingOccurrences(of: "\n", with: "\\n"))'")
        self.continuation.resume(returning: response)
    }
    
    deinit {
        self.timer?.invalidate()
        self.timer = nil
    }
}

/// A stream-based serial command queue with an asynchronous (Swift 5.5 and later) interface.
/// Using this class, we spin a long-lived `Thread` that handles all the I/O via a `RunLoop`.
public final class StreamCommandQueue: Thread {

    /// Error conditions while sending and receiving commands over the stream
    public enum Error: Swift.Error {
        case communication      /// A low-level error while opening, sending, receiving, or closing the underlying IOStream
        case timeout            /// The request was not answered within the specified time
        case invalidEncoding    /// The peer returned data with an invalid encoding
        case shutdown           /// The command queue has been instructed to shutdown
    }

    /// The delegate protocol
    public typealias Delegate = _StreamCommandQueueDelegate

    var loop: RunLoop!
    let input: InputStream
    let output: OutputStream
    let semaphore: DispatchSemaphore = .init(value: 0)
    private var activeCommand: StreamCommand? {
        didSet {
            logger.trace( self.activeCommand != nil ? "active command now \(self.activeCommand!)" : "no active command")
        }
    }
    let termination: String

    /// The delegate
    public weak var delegate: Delegate?
    
    /// Create using an input stream and an output stream.
    public init(input: InputStream, output: OutputStream, termination: String = "", delegate: Delegate? = nil) {
        self.input = input
        self.output = output
        self.termination = termination
        self.delegate = delegate
        super.init()
        self.name = "dev.cornucopia.Swift-UDS.StreamCommandQueue"
        #if canImport(ObjectiveC)
        self.threadPriority = 0.9 // we need to serve hardware requests
        #endif
        self.start()
        self.semaphore.wait() // block until the dedicated io thread has been started
    }
    
    public override func main() {
        
        self.loop = RunLoop.current
        self.semaphore.signal()
        
        self.input.delegate = self
        self.output.delegate = self
        self.input.schedule(in: self.loop, forMode: .common)
        self.output.schedule(in: self.loop, forMode: .common)
        logger.trace("\(self.name!) entering runloop")
        while !self.isCancelled {
            self.loop.run(until: Date() + 1)
        }
        logger.trace("\(self.name!) exited runloop")
        if let activeCommand = activeCommand {
            activeCommand.resumeContinuation(throwing: .timeout)
            self.activeCommand = nil
        }
        self.input.remove(from: self.loop, forMode: .common)
        self.output.remove(from: self.loop, forMode: .common)
        self.input.delegate = nil
        self.output.delegate = nil
        self.input.close()
        self.output.close()
    }

    /// Sends a string command over the stream and waits for a response.
    public func send(string: String, timeout: TimeInterval) async throws -> String {

        let response: String = try await withCheckedThrowingContinuation { continuation in
            
            self.loop.perform {
                precondition(self.activeCommand == nil, "Tried to send a command while another one has not been answered yet!")
                
                self.activeCommand = StreamCommand(string: string, timeout: timeout, termination: self.termination, continuation: continuation) {
                    self.timeoutActiveCommand()
                }
                self.outputActiveCommand()
            }
            
        }
        return response
    }
    
    /// Cancels the I/O thread and safely shuts down the streams.
    /// **NOTE**: If you don't call this function, the I/O thread in the background will never stop and the instance will leak.
    public func shutdown() {
        self.cancel()
    }
    
    deinit {
        logger.trace("\(self.name!) destroyed")
    }
}

//MARK:- Helpers
private extension StreamCommandQueue {

    func outputActiveCommand() {
        assert(self == Thread.current)

        guard self.input.streamStatus == .open else { return self.input.open() }
        guard self.output.streamStatus == .open else { return self.output.open() }
        guard self.output.hasSpaceAvailable else { return }
        guard let command = self.activeCommand else { fatalError() }
        guard command.canWrite else {
            logger.trace("command sent, waiting for response...")
            return
        }
        command.write(to: self.output)
    }

    func inputActiveCommand() {
        assert(self == Thread.current)

        guard self.input.streamStatus == .open else { return }
        guard self.input.hasBytesAvailable else { return }
        guard let command = self.activeCommand else {
            var tempBuffer: [UInt8] = .init(repeating: 0, count: 512)
            let read = self.input.read(&tempBuffer, maxLength: tempBuffer.count)
            guard read > 0 else { return }
            logger.info("ignoring \(read) unsolicited bytes")
            self.delegate?.streamCommandQueue(self, didReceiveUnsolicitedData: Data(tempBuffer[0..<read]))
            return
        }
        guard command.canRead else {
            logger.info("command not ready for reading...")
            return
        }
        command.read(from: self.input)
        if command.isCompleted {
            command.resumeContinuation()
            self.activeCommand = nil
        }
    }
    
    func timeoutActiveCommand() {
        assert(self == Thread.current)

        guard let command = self.activeCommand else {
            logger.error("received timeout for non-existing command")
            return
        }
        logger.info("command timed out after \(command.timeout) seconds.")
        command.resumeContinuation(throwing: .timeout)
        self.activeCommand = nil
    }
    
    func handleErrorCondition(stream: Stream, event: Stream.Event) {
        assert(self == Thread.current)

        logger.info("error condition on stream \(stream): \(event)")
        self.input.delegate = nil
        self.output.delegate = nil
        if let command = self.activeCommand {
            command.resumeContinuation(throwing: .communication)
            self.activeCommand = nil
        }
    }
}

extension StreamCommandQueue: StreamDelegate {

    public func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        assert(self == Thread.current)

        logger.trace("received stream \(aStream), event \(eventCode) in thread \(Thread.current)")

        switch (aStream, eventCode) {

            case (self.input, .openCompleted):
                self.delegate?.streamCommandQueue(self, inputStreamReady: self.input)
                self.outputActiveCommand()

            case (self.output, .openCompleted):
                self.delegate?.streamCommandQueue(self, outputStreamReady: self.output)
                self.outputActiveCommand()

            case (self.output, .hasSpaceAvailable):
                self.outputActiveCommand()

            case (self.input, .hasBytesAvailable):
                self.inputActiveCommand()

            case (_, .endEncountered), (_, .errorOccurred):
                self.handleErrorCondition(stream: aStream, event: eventCode)
                self.delegate?.streamCommandQueue(self, unexpectedEvent: eventCode, on: aStream)

            default:
                logger.trace("unhandled \(aStream): \(eventCode)")
                break
        }
    }
}
