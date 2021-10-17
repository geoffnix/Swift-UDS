//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
public extension UDS {

    typealias AddressAndLengthFormatIdentifier = UInt8
    typealias BlockSequenceCounter = UInt8
    typealias Compression = UInt8 // actually, just a nibble
    typealias DataIdentifier = UInt16
    typealias DataIdentifier8 = UInt8
    typealias DataFormatIdentifier = UInt8
    typealias DataRecord = [UInt8]
    typealias Encryption = UInt8 // actually, just a nibble
    typealias GroupOfDTC = UInt32 // actually, just two or three bytes
    typealias Header = UInt32
    typealias MemorySize = UInt8 // 0x01 - 0xFF, in reality a lot less though
    typealias ParameterId = UInt8 // 0x01 - 0xFF, in reality a lot less though
    typealias PositionInRecord = UInt8
    typealias RoutineIdentifier = UInt16
    typealias RoutineControlOptionRecord = [UInt8]
    typealias SecurityLevel = UInt8
    typealias TransferAddress = [UInt8]
    typealias TransferLength = [UInt8]
    typealias TransferRequestParameterRecord = [UInt8]
}
