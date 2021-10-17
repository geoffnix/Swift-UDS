//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
public extension UDS {
    
    /// Higher level errors, NOT defined in ISO14229-1
    enum Error: Swift.Error, Equatable {
        
        case busError(string: String)
        case encoderError(string: String)
        case decoderError(string: String)
        case disconnected
        case `internal`
        case invalidCharacters
        case malformedService // local error
        case noResponse
        case timeout
        case udsNegativeResponse(code: UDS.NegativeResponseCode)
        case unexpectedResult(string: String)
        case unsuitableAdapter
        case unrecognizedCommand
        case ok /// positive response
    }    
}

