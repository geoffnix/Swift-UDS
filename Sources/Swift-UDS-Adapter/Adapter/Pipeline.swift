//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import CornucopiaCore
import Foundation
import Swift_UDS

private let logger = Cornucopia.Core.Logger(category: "UDS.Pipeline")

extension UDS {

    /// An UDS command pipeline.
    /// This pipeline is implemented as an `actor`, hence can only be used from asynchronous contexts, but
    /// in return you'll get thread-safety and reentrance.
    public final actor Pipeline {

        public var logFilePath: String? = nil
        nonisolated public let adapter: UDS.Adapter
        private var logFile: FileHandle? = nil
        private var logQ: DispatchQueue = DispatchQueue(label: "dev.cornucopia.Swift-UDS.Pipeline-Logging", qos: .background)
        private var currentTask: Task<UDS.Message, Swift.Error>?

        /// Create a pipeline using an `adapter` as the sink.
        public init(adapter: UDS.Adapter) {
            precondition(adapter.state.isConnected, "At pipeline construction time, the adapter needs to be in a connected state")
            self.adapter = adapter
            logger.debug("UDS Pipeline with adapter \(adapter) ready.")
        }

        /// Starts logging by creating a log file in the specified directory.
        /// A given `header` will be written into the file, if supplied.
        /// Remember to give it a postfix of `\n`, if you want.
        public func startLogging(header: String = "") {

            let dir = FileManager.CC_pathInCachesDirectory(suffix: "dev.cornucopia.CornucopiaUDS")
            do {
                try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: nil)
                let logFilePath = "\(dir)/\(UUID())-uds.csv"
                FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
                self.logFilePath = logFilePath
                self.logFile = FileHandle(forWritingAtPath: logFilePath)
                guard self.logFile != nil else { throw NSError(domain: "dev.cornucopia.CornucopiaUDS", code: 7, userInfo: nil) }
                if !header.isEmpty, let headerData = header.data(using: .utf8) {
                    self.logFile?.write(headerData)
                }
            } catch {
                logger.notice("Can't create log file: \(error)")
            }
        }

        /// Stops logging, flushing the current logging file (if necessary).
        public func stopLogging() {
            guard let logFile = self.logFile else { return }
            self.logQ.async {
                do {
                    try logFile.close()
                } catch {
                    logger.info("Can't close log file: \(error)")
                }
                Task { await self.finalizeLog() }
            }
        }

        /// Send a requested service command down the pipeline and returns the result asynchronously.
        /// NOTE: If the pipeline is busy, this might take a while.
        public func send(to: UDS.Header, reply: UDS.Header = 0, service: UDS.Service) async throws -> UDS.Message {
            // check whether there is another command running
            while let task = self.currentTask {
                _ = try? await task.value
            }

            self.currentTask = Task<UDS.Message, Swift.Error> {
                defer { self.currentTask = nil }
                let payload = service.payload
                guard payload.count > 0 else { throw UDS.Error.malformedService }
                let message = UDS.Message(id: to, reply: reply, bytes: payload)

                guard let logFile = self.logFile else {
                    return try await self.adapter.sendUDS(message)
                }

                let requestString = "\(message.id, radix: .hex),\(payload, radix: .hex, toWidth: 2)\n"
                
                do {
                    let reply = try await self.adapter.sendUDS(message)
                    let replyString = "\(reply.id, radix: .hex),\(reply.bytes, radix: .hex, toWidth: 2)\n"

                    self.logQ.async {
                        try? logFile.write(contentsOf: requestString.data(using: .utf8)!)
                        try? logFile.write(contentsOf: replyString.data(using: .utf8)!)
                    }
                    return reply
                } catch {
                    let replyString = "ERROR: \(error)\n"
                    
                    self.logQ.async {
                        try? logFile.write(contentsOf: requestString.data(using: .utf8)!)
                        try? logFile.write(contentsOf: replyString.data(using: .utf8)!)
                    }
                    throw error
                }
            }
            
            let result = try await self.currentTask!.value
            return result
        }
    }
}

extension UDS.Pipeline {
    
    private func finalizeLog() {
        self.logFile = nil
    }
}
