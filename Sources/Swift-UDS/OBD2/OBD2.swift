//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import CornucopiaCore
import Foundation

public extension UDS {

    enum OBD2 {

        enum MessageConverter {
            case ascii(range: Range<Int>? = nil)
            case pids(offset: UInt8)
            case monitorStatusSinceDtcCleared
            case uas(_ id: UDS.UnitAndScalingId)
            case uint8
            case localized
        }

        struct MessageSpec {

            let sid: UInt8
            let pid: UInt8
            let mnemonic: String
            let len: Int
            let converter: MessageConverter
            let unit: Unit?

            init(sid: UInt8, pid: UInt8, mnemonic: String, len: Int, converter: MessageConverter, unit: Unit? = nil) {
                self.sid = sid
                self.pid = pid
                self.mnemonic = mnemonic
                self.len = len
                self.converter = converter
                self.unit = unit
            }

            func convert(message: UDS.Message) -> Any? {

                switch self.converter {

                    case .ascii(let range):
                        let range = range ?? 0..<message.bytes.count
                        let startIndex = 2 + range.startIndex
                        let endIndex = min(2 + range.endIndex, message.bytes.count - 1)
                        let asciiBytes = message.bytes[startIndex...endIndex]
                        return asciiBytes.filter { $0 > 0x08 && $0 < 0x80 }.map { String(format: "%c", $0) }.joined()

                    case .pids(let offset):
                        let pidBytes = message.bytes[2..<6]
                        var pids: [UInt8] = []
                        for pid in 0..<32 {
                            let byte = pidBytes[pidBytes.startIndex + (pid / 8)]
                            let bit: UInt8 = 1 << (7 - (pid % 8))
                            if byte & bit == bit {
                                pids.append(offset + 1 + UInt8(pid))
                            }
                        }
                        return pids

                    case .monitorStatusSinceDtcCleared:
                        let MIL: Bool = message.bytes[2] & 0x80 == 0x80
                        let DTC_CNT = message.bytes[2] & 0x7F
                        let MIS_SUP = message.bytes[3] & 0x01 == 0x01
                        let FUEL_SUP = message.bytes[3] & 0x02 == 0x02
                        let CCM_SUP = message.bytes[3] & 0x04 == 0x04
                        let hasCompressionIgnition = message.bytes[3] & 0x08 == 0x08
                        let MIS_RDY = message.bytes[4] & 0x10 == 0x10
                        let FUEL_RDY = message.bytes[4] & 0x20 == 0x20
                        let CCM_RDY = message.bytes[4] & 0x40 == 0x40
                        _ = message.bytes[4] & 0x80 == 0x80 // ISO/SAE reserved
                        return MonitorStatusSinceDtcCleared(milOn: MIL,
                                                            dtcCount: Int(DTC_CNT),
                                                            misfireMonitoringSupported: MIS_SUP,
                                                            misfireMonitoringReady: MIS_RDY,
                                                            comprehensiveComponentMonitoringSupported: CCM_SUP,
                                                            comprehensiveComponentMonitoringReady: CCM_RDY,
                                                            fuelSystemMonitoringSupported: FUEL_SUP,
                                                            fuelSystemMonitoringReady: FUEL_RDY,
                                                            hasCompressionIgnition: hasCompressionIgnition)

                    case .uas(let uasId):
                        guard message.bytes.count >= 2 + self.len else { return nil }
                        let slice = message.bytes[message.bytes.count - self.len..<message.bytes.count]
                        let bytes = Array(slice)
                        let (double, unit) = uasId.doubleUnit(for: bytes)
                        return Measurement(value: double, unit: unit)

                    case .uint8:
                        guard let unit = self.unit else { fatalError(".uint8 conversion needs a unit set")}
                        let uint8 = message.bytes.last!
                        return Measurement(value: Double(uint8), unit: unit)

                    case .localized:
                        let uint8 = message.bytes.last!
                        return "OBD2_\(self.mnemonic)_\(uint8, radix: .hex, toWidth: 2)".uds_localized
                }
            }
        }
        
        static let messageSpecs: [MessageSpec] = [
            // 0x01 – Current Data
            //
            // 0100
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.pids_00_1F, mnemonic: "PIDS_A", len: 1, converter: .pids(offset: 0x00)),
            // 0101
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.monitorStatusSinceDtcCleared, mnemonic: "MONITOR_STATUS_SINCE_DTC_CLEARED", len: 4, converter: .monitorStatusSinceDtcCleared),
            // 0105
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.engineCoolantTemperature, mnemonic: "COOLANT_TEMP", len: 1, converter: .uint8, unit: UnitTemperature.celsius),
            // 010C
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.engineRPM, mnemonic: "ENGINE_RPM", len: 2, converter: .uas(.rotationalFrequency)),
            // 010D
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.vehicleSpeed, mnemonic: "VEHICLE_SPEED", len: 1, converter: .uint8, unit: UnitSpeed.kilometersPerHour),
            // 011C
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.standardsCompliance, mnemonic: "OBD_STANDARD", len: 1, converter: .localized),
            // 011F
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.engineRunTime, mnemonic: "ENGINE_RUNTIME", len: 2, converter: .uas(.secondPerBitUnsigned)),
            // 0152
            MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.fuelType, mnemonic: "FUEL_TYPE", len: 1, converter: .localized),
            
            // 0x09 – Request Vehicle Information
            //
            // 0902
            MessageSpec(sid: ServiceId.vehicleInformation, pid: VehicleInformationType.vin, mnemonic: "VIN", len: 20, converter: .ascii(range: 1..<20)),
            // 0904
            MessageSpec(sid: ServiceId.vehicleInformation, pid: VehicleInformationType.calibrationId, mnemonic: "CAL_ID", len: 0, converter: .ascii()),
            // 090A
            MessageSpec(sid: ServiceId.vehicleInformation, pid: VehicleInformationType.ecuName, mnemonic: "ECU_NAME", len: 0, converter: .ascii()),
            // 090D
            MessageSpec(sid: ServiceId.vehicleInformation, pid: VehicleInformationType.ecuSerialNumber, mnemonic: "ECU_SN", len: 0, converter: .ascii()),
            // 090F
            MessageSpec(sid: ServiceId.vehicleInformation, pid: VehicleInformationType.exhaustRegulationOrTypeApprovalNumber, mnemonic: "EROTAN", len: 0, converter: .ascii()),

            
            //MessageSpec(sid: ServiceId.currentPowertrainDiagnosticsData, pid: CurrentPowertrainDiagnosticsDataType.engineRPM, mnemonic: "ENGINE_RPM", converter: .uint8, unit: UnitTemperature.celsius)
        ]
    }
}

public extension UDS.OBD2 {

    struct MonitorStatusSinceDtcCleared {

        let milOn: Bool
        let dtcCount: Int
        let misfireMonitoringSupported: Bool
        let misfireMonitoringReady: Bool
        let comprehensiveComponentMonitoringSupported: Bool
        let comprehensiveComponentMonitoringReady: Bool
        let fuelSystemMonitoringSupported: Bool
        let fuelSystemMonitoringReady: Bool
        let hasCompressionIgnition: Bool
    }
}
