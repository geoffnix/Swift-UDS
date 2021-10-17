//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Swift_UDS

extension Bool {
    @_transparent var atValue: String { self ? "1" : "0" }
}

extension String {
    
    var atIsLineFromECU: Bool {
        guard self.rangeOfCharacter(from: UDS.ecuCharacterSet.inverted) == nil else { return false }
        return true
    }
}

extension String {
    
    static func atCanHexLine(from: [UInt8]) -> Self {
        var string = ""
        from.forEach { byte in
            let hexByte = String(format: "%02X", byte)
            string += hexByte
        }
        return string
    }
}
