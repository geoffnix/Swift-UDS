//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
public protocol _UDSBusProtocolEncoder {

    func encode(_ bytes: [UInt8]) throws -> [UInt8]
}

public protocol _UDSBusProtocolDecoder {

    func decode(_ bytes: [UInt8]) throws -> [UInt8]
}

public extension UDS {

    typealias BusProtocolEncoder = _UDSBusProtocolEncoder
    typealias BusProtocolDecoder = _UDSBusProtocolDecoder
}
