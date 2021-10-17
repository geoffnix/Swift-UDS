//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import CornucopiaCore

public extension UDS.OBD2 {

    /// A Diagnostic Trouble Code (DTC) as defined by ISO 15031-6/SAE J2012-2007
    struct DTC: CustomStringConvertible, RawRepresentable {
        public typealias RawValue = String
        public static let Length: Int = 5 // e.g. 'P0180'

        public enum StorageArea: CaseIterable {
            case stored, pending, permanent

            public var service: UDS.Service {
                switch self {
                    case .stored: return .storedDTCs
                    case .pending: return .pendingDTCs
                    case .permanent: return .permanentDTCs
                }
            }
        }

        public enum Kind: String {
            case P
            case C
            case B
            case U
        }
        let kind: Kind
        public var rawValue: String

        init(from bytes: [UInt8]) {

            guard bytes.count == 2 else { fatalError() }
            // conversion as per ISO 15031-6/SAE J2012-2007
            let A = bytes[0]
            let B = bytes[1]
            let firstCharacter = A >> 6
            switch firstCharacter {
                case 0b00: self.kind = .P
                case 0b01: self.kind = .C
                case 0b10: self.kind = .B
                case 0b11: self.kind = .U
                default: fatalError()
            }
            let secondCharacterValue = (A & 0b00110000) >> 4
            let thirdCharacterValue = A & 0x0F
            let fourthCharacterValue = B >> 4
            let fifthCharacterValue = B & 0x0F
            self.rawValue = self.kind.rawValue + [secondCharacterValue, thirdCharacterValue, fourthCharacterValue, fifthCharacterValue].map { String($0, radix: 16, uppercase: true) }.joined()
        }

        public init?(rawValue: String) {
            guard rawValue.count == Self.Length else { return nil }
            guard let kind = Kind(rawValue: String(rawValue[0])) else { return nil }
            guard "0123".contains(rawValue[1]) else { return nil }
            guard "0123456789ABCDEF".contains(rawValue[2]) else { return nil }
            guard "0123456789ABCDEF".contains(rawValue[3]) else { return nil }
            guard "0123456789ABCDEF".contains(rawValue[4]) else { return nil }
            self.kind = kind
            self.rawValue = rawValue
        }

        public var bytes: [UInt8] {

            let firstCharacter: UInt8 = {
                switch self.kind {
                    case .P: return 0b00
                    case .C: return 0b01
                    case .B: return 0b10
                    case .U: return 0b11
                }
            }() << 6
            let secondCharacter: UInt8 = {
                switch self.rawValue[1] {
                    case "0": return 0b00
                    case "1": return 0b01
                    case "2": return 0b10
                    case "3": return 0b11
                    default: fatalError()
                }
            }() << 4
            let thirdCharacter: UInt8 = .init(self.rawValue[2...2], radix: 16) ?? 0
            let B: UInt8 = .init(self.rawValue[3...4], radix: 16) ?? 0
            let A = firstCharacter | secondCharacter | thirdCharacter
            return [A, B]
        }
        public var description: String { self.rawValue }

    }
}

public extension UDS.OBD2.DTC {

    @propertyWrapper
    struct Stringified: Codable {

        public let wrappedValue: UDS.OBD2.DTC

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let dtc = UDS.OBD2.DTC(rawValue: string) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "'\(string)' is not a valid DTC") }
            self.wrappedValue = dtc
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(self.wrappedValue.rawValue)
        }

        public init(wrappedValue: UDS.OBD2.DTC) {
            self.wrappedValue = wrappedValue
        }
    }
}
