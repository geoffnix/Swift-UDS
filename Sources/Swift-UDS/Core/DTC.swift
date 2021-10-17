//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
public extension UDS {

    struct DTC: Codable {

        public enum ExtendedDataRecordNumber: UInt8 {

            // FIXME: Add more from SAE J1979-DA
            case allRegulatedEmissionsOBD  = 0xFE
            case all                       = 0xFF
        }

        public enum FormatIdentifier: UInt8 {

            case SAE_J2012_DA_00  = 0x00
            case ISO_14229_1      = 0x01
            case SAE_J1939_73     = 0x02
            case ISO_11992_4      = 0x03
            case SAE_J2021_DA_04  = 0x04
        }

        public enum FunctionalGroupIdentifier: UInt8 {

            case emissionsSystem  = 0x33
            case safetySystem     = 0xD0
            case vobd             = 0xFE
        }

        public struct SeverityMask: OptionSet {

            public static let class0            = Self(rawValue: 1 << 0)
            public static let class1            = Self(rawValue: 1 << 1)
            public static let class2            = Self(rawValue: 1 << 2)
            public static let class3            = Self(rawValue: 1 << 3)
            public static let class4            = Self(rawValue: 1 << 4)
            public static let maintenanceOnly   = Self(rawValue: 1 << 5)
            public static let checkAtNextHalt   = Self(rawValue: 1 << 6)
            public static let checkImmediately  = Self(rawValue: 1 << 7)

            public let rawValue: UInt8

            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
        }

        public struct StatusMask: OptionSet {

            public static let testFailed                           = Self(rawValue: 1 << 0)
            public static let testFailedThisOperationCycle         = Self(rawValue: 1 << 1)
            public static let pendingDTC                           = Self(rawValue: 1 << 2)
            public static let confirmedDTC                         = Self(rawValue: 1 << 3)
            public static let testNotCompletedSinceLastClear       = Self(rawValue: 1 << 4)
            public static let testFailedSinceLastClear             = Self(rawValue: 1 << 5)
            public static let testNotCompletedThisOperationCycle   = Self(rawValue: 1 << 6)
            public static let warningIndicatorRequested            = Self(rawValue: 1 << 7)

            public let rawValue: UInt8

            public init(rawValue: UInt8) {
                self.rawValue = rawValue
            }
        }

        public let bytes: [UInt8]

        init(from bytes: [UInt8]) {
            self.bytes = bytes
        }
    }
}
