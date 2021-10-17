//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
extension UDS {

    /// Common Vehicle Bus Protocols
    public enum BusProtocol: String, RawRepresentable, CustomStringConvertible {
        case unknown        = "?"
        // Basic
        case auto           = "0"
        case j1850_PWM      = "1"
        case j1850_VPWM     = "2"
        case iso9141_2      = "3"
        case kwp2000_5KBPS  = "4"
        case kwp2000_FAST   = "5"
        case can_11B_500K   = "6"
        case can_29B_500K   = "7"
        case can_11B_250K   = "8"
        case can_29B_250K   = "9"
        case can_SAE_J1939  = "A"
        case user1_11B_125K = "B"
        case user2_11B_50K  = "C"

        public var numberOfHeaderCharacters: Int { self.broadcastHeader.count }

        public var broadcastHeader: String {
            switch self {
                case .can_11B_250K, .can_11B_500K, .user1_11B_125K, .user2_11B_50K:
                    return "7DF"
                case .can_29B_250K, .can_29B_500K:
                    return "18DB33F1"
                case .kwp2000_5KBPS, .kwp2000_FAST:
                    return "81F110"
                case .j1850_PWM:
                    return "616AF1"
                case .j1850_VPWM:
                    return "686AF1"
                case .iso9141_2:
                    return "486B10"
                default:
                    preconditionFailure("Not yet implemented")
            }
        }

        public var isValid: Bool { self != .unknown && self != .auto }
        public var isKWP: Bool { self == .kwp2000_FAST || self == .kwp2000_5KBPS }
        public var isCAN: Bool { 6...0xD ~= UInt8(self.rawValue, radix: 16) ?? 0 }

        public var description: String { "OBD2_OBD_BUSPROTO_\(self.rawValue)".uds_localized }
    }
}

