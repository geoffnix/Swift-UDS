//
//  Cornucopia – (C) Dr. Lauer Information Technology
//
import Foundation

public extension UDS {

    /// Unit and Scaling Ids (OAS) as defined by SAE J1979DA:201408, Appendix E
    enum UnitAndScalingId: UInt8 {

        case rotationalFrequency                = 0x07
        case secondPerBitUnsigned               = 0x11

        func doubleUnit(for bytes: [UInt8]) -> (Double, Unit) {
            switch self {
                case .rotationalFrequency:
                    let hi = UInt(bytes[0])
                    let lo = UInt(bytes[1])
                    return (0.25 * Double(hi << 8 + lo), UnitSpeed.CC_RPM)
                case .secondPerBitUnsigned:
                    let hi = UInt(bytes[0])
                    let lo = UInt(bytes[1])
                    return (1.0 * Double(hi << 8 + lo), UnitDuration.seconds)
            }
        }
    }
}
