//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
public struct NullProtocolEncoder: UDS.BusProtocolEncoder {

    public let maximumFrameLength: Int

    public init(maximumFrameLength: Int) {
        self.maximumFrameLength = maximumFrameLength
    }

    public func encode(_ bytes: [UInt8]) throws -> [UInt8] {

        guard bytes.count <= maximumFrameLength else {
            throw UDS.Error.encoderError(string: "Message w/ \(bytes.count) bytes too long. This adapter only supports messages up to length \(maximumFrameLength)")
        }
        return bytes
    }
}

public class NullProtocolDecoder: UDS.BusProtocolDecoder {

    public init() { }

    public func decode(_ bytes: [UInt8]) throws -> [UInt8] { bytes }
}
