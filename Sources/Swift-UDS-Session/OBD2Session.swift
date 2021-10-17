//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Foundation
import Swift_UDS
import Swift_UDS_Adapter

extension UDS {

    /// An encapsulation of an OBD2 Diagnostic Session, providing high level calls as per SAEJ1979(DA)-2014
    public actor OBD2Session {

        public typealias TypedResult<SuccessfulResponseType> = Result<SuccessfulResponseType, UDS.Error>
        public typealias TypedResultHandler<SuccessfulResponseType> = (TypedResult<SuccessfulResponseType>) -> ()

        private let pipeline: UDS.Pipeline
        private let header: UDS.Header
        private let reply: UDS.Header

        /// Create an OBD2 session for communicating with the specified target address.
        public init(with id: UDS.Header = 0x7DF, replyAddress: UDS.Header = 0, via pipeline: UDS.Pipeline) {
            self.pipeline = pipeline
            self.header = id
            self.reply = replyAddress
        }

        /// Read specified `service`. This is helpful if you don't know the expected type of the response.
        public func read(service: UDS.Service) async throws -> OBD2Response {
            try await request(service: service)
        }

        /// Read DTCs for the given `storage` area.
        public func readDTCs(storage: UDS.OBD2.DTC.StorageArea) async throws -> [UDS.OBD2.DTC] {
            let response: OBD2DTCResponse = try await self.request(service: storage.service)
            return response.dtc
        }
        
        /// Read a `String` value via the given `service`.
        public func readString(service: UDS.Service) async throws -> String {
            let response: OBD2Response = try await request(service: service)
            guard response.valueType == .string else { throw UDS.Error.unexpectedResult(string: "Expected String, but got \(response.valueType)") }
            return response.value! as! String
        }

        /// Read a `Measurement` via the given `service`.
        public func readMeasurement(service: UDS.Service) async throws -> Measurement<Unit> {
            let response: OBD2Response = try await request(service: service)
            guard response.valueType == .measurement else { throw UDS.Error.unexpectedResult(string: "Expected String, but got \(response.valueType)") }
            return response.value! as! Measurement
        }
    }
}

internal extension UDS.OBD2Session {

    func request<T: UDS.ConstructableViaMessage>(service: UDS.Service) async throws -> T {
        guard !service.payload.isEmpty else { throw UDS.Error.malformedService }

        let message = try await self.pipeline.send(to: self.header, reply: self.reply, service: service)
        guard message.bytes[0] != UDS.NegativeResponse else {
            let negativeResponseCode = UDS.NegativeResponseCode(rawValue: message.bytes[2]) ?? .undefined
            throw UDS.Error.udsNegativeResponse(code: negativeResponseCode)
        }
        let response = T(message: message)
        return response
    }
}
