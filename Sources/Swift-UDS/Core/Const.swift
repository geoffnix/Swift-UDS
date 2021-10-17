//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Foundation

public extension UDS {
    
    static let canBroadcastHeader11: Header = .init(0x7DF)
    static let canBroadcastHeader29: Header = .init(0x18DB33F1)
    
    static let ecuCharacterSet: CharacterSet = .init(charactersIn: "0123456789ABCDEF ")
}
