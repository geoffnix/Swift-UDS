//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import CornucopiaCore
import Foundation
import Swift_UDS
import Swift_UDS_Adapter

private var logger = Cornucopia.Core.Logger()

extension UDS {
    
    /// An encapsulation of a UDS Diagnostic Session, providing high level calls as per ISO14229-1:2020
    public actor DiagnosticSession {
        
        private let id: UDS.Header
        private let reply: UDS.Header
        private let pipeline: UDS.Pipeline
        private let mtu: Int

        public var activeTransferProgress: Progress?
        
        public init(with id: UDS.Header, replyAddress: UDS.Header, via pipeline: UDS.Pipeline) {
            self.id = id
            self.reply = replyAddress
            self.pipeline = pipeline
            self.mtu = pipeline.adapter.mtu
        }
        
        //MARK:- Direct UDS Requests
        
        /// Clear stored diagnostic trouble codes
        @discardableResult
        public func clearDiagnosticInformation(groupOfDTC: GroupOfDTC) async throws -> UDS.GenericResponse {
            try await self.request(service: .clearDiagnosticInformation(groupOfDTC: groupOfDTC))
        }
        
        /// Clear all dynamically defined data identifiers
        @discardableResult
        public func clearAllDynamicallyDefinedDataIdentifiers() async throws -> UDS.GenericResponse {
            try await self.request(service: .clearAllDynamicallyDefinedDataIdentifiers)
        }
        
        /// Clear a dynamically defined data identifier
        @discardableResult
        public func clearDynamicallyDefinedDataIdentifier(_ identifier: DataIdentifier) async throws -> UDS.GenericResponse {
            try await self.request(service: .clearDynamicallyDefinedDataIdentifier(id: identifier))
        }
        
        /// Control communication
        @discardableResult
        public func communicationControl(_ controlType: CommunicationControlType, messages: CommunicationType) async throws -> UDS.GenericResponse {
            try await self.request(service: .communicationControl(controlType: controlType, communicationType: messages))
        }
        
        /// Control DTC setting
        @discardableResult
        public func controlDTCSetting(on: Bool) async throws -> UDS.GenericResponse {
            try await self.request(service: .controlDTCSettings(settingType: on ? .on : .off))
        }

        /// Define dynamically defined data identifier by identifier
        @discardableResult
        public func dynamicallyDefineIdentifier(_ identifier: DataIdentifier, byIdentifier: DataIdentifier, position: PositionInRecord, length: MemorySize) async throws -> UDS.GenericResponse {
            try await self.request(service: .dynamicallyDefineDataIdentifier(id: identifier, byIdentifier: byIdentifier, position: position, length: length))
        }
        
        /// Reset the ECU
        @discardableResult
        public func ecuReset(type: EcuResetType) async throws -> UDS.EcuResetResponse {
            try await self.request(service: .ecuReset(type: type))
        }
        
        /// Start a (non-default) diagnostic session
        @discardableResult
        public func start(type: DiagnosticSessionType) async throws -> UDS.DiagnosticSessionResponse {
            try await self.request(service: .diagnosticSessionControl(session: type))
        }
        
        /// Request the security access seed
        @discardableResult
        public func requestSeed(securityLevel: UDS.SecurityLevel) async throws -> UDS.SecurityAccessSeedResponse {
            try await self.request(service: .securityAccessRequestSeed(level: securityLevel))
        }
        
        /// Send the security access key
        @discardableResult
        public func sendKey(securityLevel: UDS.SecurityLevel, key: [UInt8]) async throws -> UDS.GenericResponse {
            try await self.request(service: .securityAccessSendKey(level: securityLevel, key: key))
        }
        
        /// Read data record
        @discardableResult
        public func readData(byIdentifier: UDS.DataIdentifier) async throws -> UDS.DataIdentifierResponse {
            try await self.request(service: .readDataByIdentifier(id: byIdentifier))
        }
        
        /// Read DTC
        @discardableResult
        public func readDTCByStatusMask(_ mask: DTC.StatusMask) async throws -> UDS.DTCResponse {
            try await self.request(service: .readDTCByStatusMask(mask: mask))
        }
        
        /// Initiate a block transfer (TESTER -> ECU)
        @discardableResult
        public func requestDownload(compression: UInt8, encryption: UInt8, address: [UInt8], length: [UInt8]) async throws -> UDS.GenericResponse {
            try await self.request(service: .requestDownload(compression: compression, encryption: encryption, address: address, length: length))
        }
        
        /// Trigger a routine
        @discardableResult
        public func routineControl(type: UDS.RoutineControlType, identifier: UDS.RoutineIdentifier, optionRecord: DataRecord = []) async throws -> UDS.GenericResponse {
            try await self.request(service: .routineControl(type: type, id: identifier, rcor: optionRecord))
        }
        
        /// Transfer a single data block. Caution: The maximum data length is adapter-specific. The use
        /// of this function is not recommended, unless you know exactly what you are doing. Better use `transferData`!
        @discardableResult
        public func transferBlock(_ block: UInt8, data: Data) async throws -> UDS.GenericResponse {
            try await self.request(service: .transferData(bsc: block, trpr: [UInt8](data)))
        }
        @discardableResult
        public func transferBlock(_ block: UInt8, data: [UInt8]) async throws -> UDS.GenericResponse {
            try await self.request(service: .transferData(bsc: block, trpr: data))
        }
        
        /// Finish a block transfer
        @discardableResult
        public func transferExit(_ optionRecord: DataRecord = []) async throws -> UDS.GenericResponse {
            try await self.request(service: .requestTransferExit(trpr: optionRecord))
        }
        
        /// Indicate tester being present
        @discardableResult
        public func testerPresent(type: UDS.TesterPresentType) async throws -> UDS.GenericResponse {
            try await self.request(service: .testerPresent(type: .sendResponse))
        }
        
        /// Write data record
        @discardableResult
        public func writeData(byIdentifier: UDS.DataIdentifier, dataRecord: DataRecord) async throws -> UDS.GenericResponse {
            try await self.request(service: .writeDataByIdentifier(id: byIdentifier, drec: dataRecord))
        }
        
        //MARK:- Aggregated / Higher Level features
        
        /// Send data via consecutive block transfer
        public func transferData(_ data: Data) async throws {
            let mtu = self.pipeline.adapter.mtu
            guard mtu >= 0xFF else { throw UDS.Error.unsuitableAdapter }
            var blockNumber: UInt8 = 1
            
            self.activeTransferProgress = .init(totalUnitCount: Int64(data.count))

            for chunk in data.CC_chunked(size: mtu) {
                _ = try await self.transferBlock(blockNumber, data: chunk)
                blockNumber = blockNumber == 0xFF ? 0x00 : blockNumber + 1
                self.activeTransferProgress!.completedUnitCount += Int64(chunk.count)
            }
            
            self.activeTransferProgress = nil
        }
        
        /// Register a number of dynamically defined data identifiers given the source identifiers.
        /// This call tries to read the source identifier first, to gather its presence and length.
        /// Returns the dynamic identifiers.
        public func defineDynamicIdentifiers(sourceIdentifiers: [DataIdentifier]) async throws -> [DataIdentifier] {
            
            var currentDynamicDataIdentifier: UInt16 = 0xF300
            var dynamicDataIdentifiers: [UInt16] = []
            
            for sourceIdentifier in sourceIdentifiers {
                guard let sourceIdentifierResponse = try? await self.readData(byIdentifier: sourceIdentifier) else {
                    logger.debug("Can't read \(sourceIdentifier, radix: .hex, prefix: true, toWidth: 4), trying the next requested one")
                    continue
                }
                
                let length = UInt8(min(0xFF, sourceIdentifierResponse.dataRecord.count))
                do {
                    try await self.dynamicallyDefineIdentifier(currentDynamicDataIdentifier, byIdentifier: sourceIdentifier, position: 1, length: length)
                    if dynamicDataIdentifiers.last != currentDynamicDataIdentifier {
                        dynamicDataIdentifiers.append(currentDynamicDataIdentifier)
                    }
                } catch {
                    guard dynamicDataIdentifiers.last == currentDynamicDataIdentifier else {
                        throw error
                    }
                    logger.debug("Couldn't add \(sourceIdentifier, radix: .hex, prefix: true, toWidth: 4) to \(currentDynamicDataIdentifier, radix: .hex, prefix: true, toWidth: 4): \(error), retrying with the next DDI")
                    currentDynamicDataIdentifier += 1
                    try await self.dynamicallyDefineIdentifier(currentDynamicDataIdentifier, byIdentifier: sourceIdentifier, position: 1, length: length)
                    dynamicDataIdentifiers.append(currentDynamicDataIdentifier)
                }
            }
            
            return dynamicDataIdentifiers
        }
    }
}

//MARK:- Private
private extension UDS.DiagnosticSession {
    
    func request<T: UDS.ConstructableViaMessage>(service: UDS.Service) async throws -> T {
        
        let message = try await self.pipeline.send(to: self.id, reply: self.reply, service: service)
        if message.bytes.count > 0, message.bytes[0] == UDS.NegativeResponse {
            let negativeResponseCode = UDS.NegativeResponseCode(rawValue: message.bytes[2]) ?? .undefined
            let error: UDS.Error = .udsNegativeResponse(code: negativeResponseCode)
            throw error
        }
        let response = T(message: message)
        return response
    }
}
