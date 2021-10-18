//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Foundation

public extension UDS {

    enum ISOTP {
        /// ISOTP uses three nibbles to encode the frame size, hence 0xFFF = 4095 is the maximum
        public static let MaximumFrameSize: Int = 4095
        /// UDS data transfers have two control bytes (0x36 #BLOCK) before the block payload comes
        public static let MaximumDataTransferSize: Int = Self.MaximumFrameSize - 2
    }
}

public extension UDS.ISOTP {
    
    /// An ISOTP encoder, see ISO15765-2
    final class Encoder: UDS.BusProtocolEncoder {
        
        public init() { }
        
        /// Encode a byte stream by inserting the appropriate framing control bytes as per ISOTP
        public func encode(_ bytes: [UInt8]) throws -> [UInt8] {
            guard bytes.count > 0 else { throw UDS.Error.encoderError(string: "Message too small (0 bytes)") }
            guard bytes.count < UDS.ISOTP.MaximumFrameSize else { throw UDS.Error.encoderError(string: "Message too long. Maximum ISOTP payload is 4095 (0xFFF) bytes") }
            
            let framedPayload = bytes.count < 7 ? self.encodeSingleFrame(payload: bytes) : self.encodeMultiFrame(payload: bytes)
            return framedPayload
        }
        
        // encodes bytes to a single frame
        private func encodeSingleFrame(payload: [UInt8]) -> [UInt8] {
            let pci = UInt8(payload.count)
            return [pci] + payload
        }
        
        // encodes bytes to multiple frames
        private func encodeMultiFrame(payload: [UInt8]) -> [UInt8] {
            var payload = payload
            let pci = 0x1000 | UInt16(payload.count)
            let pciHi = UInt8(pci >> 8 & 0xFF)
            let pciLo = UInt8(pci & 0xFF)
            let ff = [pciHi, pciLo] + payload[0..<6]
            payload.removeFirst(6)
            var bytes = ff
            var cfPci = UInt8(0x21)
            while payload.count > 0 {
                let cfPayloadCount = min(7, payload.count)
                let cf = [cfPci] + payload[0..<cfPayloadCount]
                payload.removeFirst(cfPayloadCount)
                bytes += cf
                cfPci = cfPci + 1
                if cfPci == 0x30 {
                    #if true
                    cfPci = 0x20
                    #else
                    cfPci = 0x21 //NOTE: If you want to force the ECU not responding, you might try setting the PCI to 0x21 here, thus rendering the protocol invalid
                    #endif
                }
            }
            return bytes
        }
    }
    
    /// An ISOTP decoder, see ISO15765-2
    final class Decoder: UDS.BusProtocolDecoder {
        
        public init() { }
        
        /// Decode a byte stream consisting on multiple individual concatenated frames by removing the protocol framing bytes as per ISOTP
        public func decode(_ bytes: [UInt8]) throws -> [UInt8] {
            guard bytes.count > 0 else { throw UDS.Error.decoderError(string: "Message too small (0 bytes)") }

            let unframedPayload = bytes.count < 9 ? try self.decodeSingleFrame(payload: bytes) : try self.decodeMultiFrame(payload: bytes)
            return unframedPayload
        }
        
        // decodes a single frame to bytes
        private func decodeSingleFrame(payload: [UInt8]) throws -> [UInt8] {
            let pci = payload[0]
            guard pci != 0x30 else {
                // Looks like an FC ACK frame, just pass this through
                return payload
            }
            guard pci < 0x08 else {
                throw UDS.Error.decoderError(string: "Corrupt single frame with PCI \(pci, radix: .hex, prefix: true) detected")
            }
            let border = Int(pci)
            return Array(payload[1...border])
        }
        
        // decodes multiple frames to bytes
        private func decodeMultiFrame(payload: [UInt8]) throws -> [UInt8] {
            var payload = payload
            let pciHi = payload[0]
            guard pciHi & 0xF0 == 0x10 else {
                throw UDS.Error.decoderError(string: "Corrupt FF w/ PCI \(pciHi, radix: .hex, prefix: true) detected")
            }
            let pciLo = payload[1]
            let pci = UInt16(pciHi) << 8 | UInt16(pciLo)
            let length = Int(pci & 0xFFF)
            
            var bytes = payload[2..<8]
            payload.removeFirst(8)
            var expectedCfPci: UInt8 = 0x21
            var remainingExpectedPayload = length - 6
            while remainingExpectedPayload > 0 {
                guard !payload.isEmpty else { throw UDS.Error.decoderError(string: "Payload underflow. Answer not complete") }
                let cfPci = payload.removeFirst()
                guard cfPci == expectedCfPci else { throw UDS.Error.decoderError(string: "Corrupt CF w/ PCI \(cfPci, radix: .hex, prefix: true) detected, was expecting \(expectedCfPci, radix: .hex, prefix: true)") }
                let cfPayloadSize = min(7, payload.count, remainingExpectedPayload)
                bytes += payload[0..<cfPayloadSize]
                payload.removeFirst(cfPayloadSize)
                remainingExpectedPayload -= cfPayloadSize
                expectedCfPci += 1
                if expectedCfPci == 0x30 {
                    expectedCfPci = 0x20
                }
            }
            return Array(bytes)
        }
    }
}

/// ISOTP Helpers for implementing ISOTP reception. This is probably only of use for implementing (virtual) ECUs.
public extension UDS.ISOTP {

    /// The flow control status.
    enum FlowStatus: UInt8 {
        /// Clear to send more frames.
        case clearToSend    = 0x30
        /// Buffer full, please wait for another control flow frame with `clearToSend`.
        case wait           = 0x31
        /// Overflow, please abort and resent the whole command.
        case overflow       = 0x32
    }
    
    /// The ISOTP frame type.
    enum FrameType: UInt8 {
        case single         = 0x00
        case first          = 0x01
        case consecutive    = 0x02
    }

    /// A flow control frame.
    struct FlowControlFrame {
        public let flowStatus: FlowStatus
        public let blockSize: UInt8
        public let separationTime: UInt8
        public var bytes: [UInt8] { [self.flowStatus.rawValue, self.blockSize, self.separationTime] }

        public init(flowStatus: FlowStatus = .clearToSend, blockSize: UInt8 = 0x20, separationTimeMs: UInt8 = 0x0) {
            self.flowStatus = flowStatus
            self.blockSize = blockSize
            self.separationTime = separationTimeMs
        }

        public init?(from message: UDS.Message) {
            guard message.bytes.count >= 3 else { return nil }
            guard let flowStatus = FlowStatus(rawValue: message.bytes[0]) else { return nil }
            self.flowStatus = flowStatus
            self.blockSize = message.bytes[1]
            self.separationTime = message.bytes[2]
        }
    }

    /// An ISOTP receiver.
    class Receiver {

        /// The Action after receiving another frame.
        public enum Action {
            /// Send a control flow frame
            case sendFlowControl(frame: FlowControlFrame)
            /// Wait for more frames
            case waitForMore
            /// Process the aggregated message
            case process(message: UDS.Message)
            /// Handle error
            case error(String)
        }

        /// The flow control frame.
        private let flowControlFrame: FlowControlFrame
        /// The flow control counter. When it hits 0, another flow control frame needs to be sent.
        private var flowControlCounter: UInt8 = 1
        /// The announced payload size from the FF.
        private var remainingPayloadCounter: Int = 0
        /// The current payload.
        private var payload: [UInt8] = []
        /// The aggregated message.
        private var message: UDS.Message {
            guard let first = self.messages.first else { fatalError("Message underflow") }
            return UDS.Message(id: first.id, reply: first.reply, bytes: payload)
        }
        /// The individual messages.
        private var messages: [UDS.Message] = []

        /// Initialize based on a desired block size and separation time.
        public init(blockSize: UInt8 = 0x20, separationTime: UInt8 = 0x00) {
            self.flowControlFrame = FlowControlFrame(blockSize: blockSize, separationTimeMs: separationTime)
        }

        /// Appends a frame. Returns the necessary action.
        public func received(frame: UDS.Message) -> Action {
            self.messages.append(frame)
            guard let frameType = FrameType(rawValue: frame.bytes[0] >> 4) else {
                return .error("Invalid frame type w/ PCI \(frame.bytes[0], radix: .hex, toWidth: 2)")
            }
            switch frameType {

                case .single:
                    let dl = Int(frame.bytes[0] & 0x0F)
                    let payload = Array(frame.bytes[1...dl])
                    let message = UDS.Message(id: frame.id, reply: frame.reply, bytes: payload)
                    return .process(message: message)

                case .first:
                    let pciHi: UInt16 = UInt16(frame.bytes[0] & 0x0F)
                    let pciLo: UInt16 = UInt16(frame.bytes[1])
                    let pci = pciHi << 8 | pciLo
                    self.remainingPayloadCounter = Int(pci - 6) // FF has 6 bytes of payload
                    self.payload += Array(frame.bytes.dropFirst(2))
                    self.flowControlCounter = self.flowControlFrame.blockSize
                    return .sendFlowControl(frame: self.flowControlFrame)
                    
                case .consecutive:
                    //let pciHi: UInt16 = UInt16(frame.bytes[0] & 0x0F)
                    //let pciLo: UInt16 = UInt16(frame.bytes[1])
                    //let pci = pciHi << 8 | pciLo
                    self.payload += Array(frame.bytes[1...min(7, self.remainingPayloadCounter)])
                    self.remainingPayloadCounter -= 7 // CF has a maximum of 7 bytes
                    if self.remainingPayloadCounter <= 0 {
                        return .process(message: self.message)
                    }
                    self.flowControlCounter -= 1
                    if flowControlCounter == 0 {
                        self.flowControlCounter = self.flowControlFrame.blockSize
                        return .sendFlowControl(frame: self.flowControlFrame)
                    } else {
                        return .waitForMore
                    }
            }
        }
    }
}
