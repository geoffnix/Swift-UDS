//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import CornucopiaCore
import Foundation
import Swift_UDS

private let logger = Cornucopia.Core.Logger()

extension UDS {

    /// A generic serial command adapter, i.e. using (relatively) low-cost _OBD2 to RS232_ adapters, such as
    /// ```
    ///  *==================================================
    ///  *   VENDOR       CHIPSET     MODEL
    ///  *==================================================
    ///  * ELM ELECTRONICS ELM327    Various Clones
    ///  * OBD SOLUTIONS   STN11xx   OBDLINK SX, OBDLINK MX WiFi, etc.
    ///  * OBD SOLUTIONS   STN22xx   OBDLINK MX+, OBDLINK CX, etc.
    ///  * WGSoft.de       CUSTOM    UniCarScan 2000 (CAUTION!)
    ///  *==================================================
    /// ```
    /// NOTE: `GenericSerialAdapter` is **not** thread-safe. It is only allowed to submit one command after another.
    /// If you want to be on the safe side, create a `Pipeline` and use this for all communication.
    public final class GenericSerialAdapter: BaseAdapter {
                    
        private var commandProvider: StringCommandProvider!
        private var commandQueue: StreamCommandQueue!
        
        private var header = Header(0x7DF) // start out with OBD2 broadcast header
        private var replyHeader = Header(0x000) // none set
        private var stnSendFragmentation = false
        private var stnReceiveFragmentation = false
        private var desiredBusProtocol: BusProtocol = .unknown
        private var negotiatedBusProtocol: BusProtocol = .unknown
        public internal(set) var busProtocolEncoder: BusProtocolEncoder? = nil {
            didSet { logger.debug("BusProtocolEncoder now \(self.busProtocolEncoder!)") }
        }
        public internal(set) var busProtocolDecoder: BusProtocolDecoder? = nil {
            didSet { logger.debug("BusProtocolDecoder now \(self.busProtocolDecoder!)") }
        }

        public enum ICType: String {
            case unknown = "???"
            case elm327  = "ELM327"
            case stn11xx = "STN11xx"
            case stn22xx = "STN22xx"
            case unicars = "UniCarScan"
        }
        public var icType = ICType.unknown {
            didSet {
                switch self.icType {
                    case .stn11xx:
                        self.maximumAutoSegmentationFrameLength = 0x7FF // STPX
                    case .stn22xx:
                        self.maximumAutoSegmentationFrameLength = 0xFFF // STPX
                    case .unicars:
                        self.maximumAutoSegmentationFrameLength = 0xFF  // automatic ISOTP
                    default:
                        self.maximumAutoSegmentationFrameLength = 0
                }
                self.mtu = self.maximumAutoSegmentationFrameLength > 0 ? self.maximumAutoSegmentationFrameLength : 8
            }
        }
        public var identification: String = "???"
        public var name: String = "Unspecified"
        public var vendor: String = "Unknown"
        public var serial: String = "Unknown"
        public var version: String = "Unknown"
        
        public var hasAutoSegmentation: Bool = false
        public var hasSmallFrameNoResponse: Bool = false
        public var hasFullFrameNoResponse: Bool = false
        public var canAutoFormat: Bool = true // CAN auto format is true by default for all ELM327-compatible serial adapters
        public var detectedECUs: [String] = []
        public var maximumAutoSegmentationFrameLength: Int = 0

        /// Initialize an adapter given a pair of streams and an optional `commandProvider`. The default one should be good for almost all use cases.
        public init(inputStream: InputStream, outputStream: OutputStream, commandProvider: StringCommandProvider? = nil) {
            super.init()
            self.commandProvider = commandProvider ?? DefaultStringCommandProvider()
            self.commandQueue = StreamCommandQueue(input: inputStream, output: outputStream, termination: ">", delegate: self)
        }
        
        /// Connect to the bus with a given `busProtocol`. Use `.auto` unless you know exactly which kind of bus you are connecting to.
        public override func connect(via busProtocol: BusProtocol = .auto) {
            precondition(self.state == .created, "It is only valid to call this during state .created. Current State is \(self.state)")
            self.desiredBusProtocol = busProtocol
            self.updateState(.searching)
        }

        /// Post a command, ignoring the result.
        public func post(_ stringCommand: StringCommand) async throws {
            
            guard self.state != .notFound, self.state != .gone, self.state != .unsupportedProtocol else {
                logger.notice("Ignoring commands during state \(self.state)")
                throw UDS.Error.disconnected
            }
            guard let (request, _) = self.commandProvider.provide(command: stringCommand) else {
                logger.notice("Ignoring unresolved command: \(stringCommand)")
                throw UDS.Error.malformedService
            }
            _ = try await self.sendString(request + "\r")
        }

        /// Send a UDS message and return one.
        public override func sendUDS(_ message: UDS.Message) async throws -> UDS.Message {
            
            let sid = self.canAutoFormat ? message.bytes[0] : message.bytes[1]

            var requestMessage = message
            requestMessage.bytes = try self.busProtocolEncoder!.encode(message.bytes)
            let theSendRaw = ( requestMessage.bytes.count > 8 ) && ( self.icType == .stn11xx || self.icType == .stn22xx ) ? self.stnSendRaw : self.sendRaw

            let responseMessages = try await theSendRaw(requestMessage)
            guard responseMessages.count > 0 else { throw UDS.Error.noResponse }

            let responses = responseMessages.filter { response in
                guard message.reply == 0x0 || response.id == message.reply else {
                    logger.info("""
Ignoring message with unexpected reply header \(response.id, radix: .hex, prefix: true). Expected \(message.reply, radix: .hex, prefix: true).
The presence of an unexpected frame might indicate a problem with your OBD2 adapter. Please check whether the filter masks are properly configured.
""")
                    return false
                }
                guard response.bytes[0] == UInt8(0x03) else { return true }
                guard response.bytes[1] == UDS.NegativeResponse else { return true }
                guard response.bytes[2] == sid else { return true }
                guard response.bytes[3] == UDS.NegativeResponseCode.requestCorrectlyReceivedResponsePending.rawValue else { return true }
                logger.trace("Ignoring transient UDS response \(responseMessages[0].bytes[1..<4].map { String(format: "0x%02X ", $0) }.joined())")
                return false
            }
            var bytes = [UInt8]()
            responses.forEach { response in
                bytes += response.bytes
            }
            bytes = try self.busProtocolDecoder!.decode(bytes)
            let assembled: UDS.Message = .init(id: responses.first!.id, bytes: bytes)
            return assembled
        }

        /// Send a command and expect a certain, typed, response.
        public func send<T>(_ stringCommand: StringCommand) async throws -> T {
            
            guard self.state != .notFound, self.state != .gone, self.state != .unsupportedProtocol else {
                logger.notice("Ignoring commands during state \(self.state)")
                throw UDS.Error.disconnected
            }
            
            guard let (request, responseConverter) = self.commandProvider.provide(command: stringCommand) else {
                logger.notice("Ignoring unresolved command: \(stringCommand)")
                throw UDS.Error.malformedService
            }

            let response = try await self.sendString(request + "\r")
            let result = responseConverter(response, self)
            switch result {
                case let .success(value as T):
                    return value
                case let .failure(udsError):
                    throw udsError
                case .success(let value):
                    assert(false, "Internal error: expected \(type(of: T.self)), received \(type(of: value))")
                    throw UDS.Error.internal
            }
        }
        
        /// Send a raw string and return the response.
        public func sendString(_ string: String) async throws -> String {
            var timeout = 10.0
            if case .connected = self.state {
                timeout = 5.0
            }
            return try await self.commandQueue.send(string: string, timeout: timeout)
        }

        public override func didUpdateState() {
            switch self.state {
                    
                case .searching:
                    Task { try await self.sendInitSequence() }
                    
                case .configuring:
                    Task { try await self.sendConfigSequence() }
                    
                default:
                    break
            }
        }
    }
}

//MARK:- Helpers
extension UDS.GenericSerialAdapter {
    
    /// Sends a UDS message.
    private func sendRaw(_ message: UDS.Message) async throws -> [UDS.Message] {
        
        if self.header != message.id {
            let ok: Bool = try await self.send(.setHeader(id: message.id))
            if ok {
                self.header = message.id
            }
        }
        if self.replyHeader != message.reply {
            let ok: Bool = try await self.send(.canReceiveArbitration(id: message.reply))
            if ok {
                self.replyHeader = message.reply
            }
        }
        let responses: [UDS.Message] = try await self.send(.data(bytes: message.bytes))
        return responses
    }
    
    /// Sends a UDS message by using the proprietary STPX command found on STN chipsets.
    private func stnSendRaw(_ message: UDS.Message) async throws -> [UDS.Message] {

        if self.header != message.id {
            let ok: Bool = try await self.send(.setHeader(id: message.id))
            if ok {
                self.header = message.id
            }
        }
        if self.replyHeader != message.reply {
            let ok: Bool = try await self.send(.canReceiveArbitration(id: message.reply))
            if ok {
                self.replyHeader = message.reply
            }
        }
        
        try await self.post(.stnCanTransmitAnnounce(count: message.bytes.count))
        let responses: [UDS.Message] = try await self.send(.data(bytes: message.bytes))
        return responses
    }
}

extension UDS.GenericSerialAdapter {
    
    func sendInitSequence() async throws {
        do {
            try await self.post(.dummy)
            try await self.post(.reset)
        } catch {
            print("error: \(error)")
            return self.updateState(.notFound)
        }
        let lowlevelConfiguration: [StringCommand] = [
            .spaces(on: false),
            .echo(on: false),
            .linefeed(on: false),
            .showHeaders(on: true)
        ]
        for command in lowlevelConfiguration {
            let success: Bool = try await self.send(command)
            if !success {
                logger.debug("command \(command) did not succeed")
            }
        }
        if let id: String = try? await self.send(.identify) {
            let components = id.components(separatedBy: " ")
            if components.count == 2 {
                self.identification = components[0]
                self.version = components[1]
            } else {
                self.identification = name
            }
            self.icType = .elm327
        }
        if let id: String = try? await self.send(.version1) {
            self.version = id
        }
        if let id: String = try? await self.send(.stnExtendedIdentify) {
            let components = id.components(separatedBy: " ")
            if components.count >= 3 {
                self.identification = components[0]
                self.version = components[1]
            } else {
                self.identification = id
            }
            self.icType = id.starts(with: "STN11") ? .stn11xx : .stn22xx
            self.vendor = "ScanTool.net"

            try? await self.post(.stnCanSegmentationTransmit(on: true))
            if let id: String = try? await self.send(.stnDeviceIdentify) {
                self.name = id
            }
            if let sn: String = try? await self.send(.stnSerialNumber) {
                self.serial = sn
            }
        }
        if let id: String = try? await self.send(.unicarsIdentify), id.contains("WGSoft.de") {
            self.name = id.contains("2021") ? "UniCarScan 2100" : "UniCarScan 2000"
            self.icType = .unicars
            self.vendor = "WGSoft.de"
        }

        let info = UDS.AdapterInfo(model: self.name, ic: self.identification, vendor: self.vendor, serialNumber: self.serial, firmwareVersion: self.version)
        self.updateState(.configuring(info))
    }
    
    func sendConfigSequence() async throws {
        
        // check protocol
        do {
            try await self.post(.setProtocol(p: self.desiredBusProtocol))
            try await self.post(.spaces(on: true))
            let ecus: [String] = try await self.send(.connect)
            self.detectedECUs = ecus
            try await self.post(.spaces(on: false))
            let theProtocol: UDS.BusProtocol = try await self.send(.describeProtocolNumeric)
            guard theProtocol.isValid else { throw UDS.Error.disconnected }
            self.negotiatedBusProtocol = theProtocol
        } catch {
            self.updateState(.unsupportedProtocol)
            return // no need for further configuration
        }

        // tailor for CAN
        if self.negotiatedBusProtocol.isCAN {

            try await self.post(.adaptiveTiming(on: false))
            self.canAutoFormat = try await self.send(.canAutoFormat(on: true))

            if self.icType == .stn11xx || self.icType == .stn22xx {
                // enlarge ISOTP flow control timeouts a bit
                try await self.post(.stnCanSegmentationTimeouts(flowControl: 255, consecutiveFrame: 255))
                try await self.post(.stnCanSegmentationTransmit(on: true))
            }
            do {
                _ = try await self.post(.probeAutoSegmentation)
                self.hasAutoSegmentation = true
            } catch {
                self.hasAutoSegmentation = false
            }
            let smallFrameNoResponseResult: String = try await self.send(.probeSmallFrameNoResponse)
            self.hasSmallFrameNoResponse = smallFrameNoResponseResult.CC_trimmed().isEmpty
        }

        self.installProtocolHandlers()
    }

    func installProtocolHandlers() {
        let proto = self.negotiatedBusProtocol
        
        switch proto {
                
            case .unknown, .auto:
                fatalError("Invalid bus protocol \(proto)")

            case .j1850_PWM, .j1850_VPWM:
                self.busProtocolDecoder = UDS.J1850.Decoder()
                self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: 7)

            case .iso9141_2:
                self.busProtocolDecoder = UDS.ISO9141.Decoder()
                self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: 7)

            case .kwp2000_5KBPS, .kwp2000_FAST:
                self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: 7)
                self.busProtocolDecoder = UDS.KWP.Decoder()
                
            case .can_SAE_J1939, .user1_11B_125K, .user2_11B_50K, .can_11B_500K, .can_29B_500K, .can_11B_250K, .can_29B_250K:
                if self.hasAutoSegmentation {
                    self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: self.maximumAutoSegmentationFrameLength)
                } else {
                    let maximumFrameLength = self.canAutoFormat ? 7 : 8
                    self.busProtocolEncoder = NullProtocolEncoder(maximumFrameLength: maximumFrameLength)
                }
                self.busProtocolDecoder = UDS.ISOTP.Decoder()
        }
        self.updateState(.connected(proto))
    }
}

extension UDS.GenericSerialAdapter: StreamCommandQueue.Delegate {

    public func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, inputStreamReady stream: InputStream) {
        NotificationCenter.default.post(name: UDS.AdapterCanInitHardware, object: self)
    }
    
    public func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, outputStreamReady stream: OutputStream) {
        logger.trace("not yet implemented")
    }
    
    public func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, didReceiveUnsolicitedData data: Data) {
        logger.trace("not yet implemented")
    }
    
    public func streamCommandQueue(_ streamCommandQueue: StreamCommandQueue, unexpectedEvent event: Stream.Event, on stream: Stream) {
        logger.trace("not yet implemented")
    }
}
