//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Swift_UDS

public typealias ResponseResult = Result<Any, UDS.Error>
public typealias ResponseConverter = (String, UDS.GenericSerialAdapter) -> ResponseResult

public protocol _GenericSerialAdapterStringCommandProvider {
    func provide(command: UDS.GenericSerialAdapter.StringCommand) -> (string: String, responseConverter: ResponseConverter)?
}

public extension UDS.GenericSerialAdapter {

    typealias StringCommandProvider = _GenericSerialAdapterStringCommandProvider

    enum StringCommand: Equatable {

        // basic (ELM327-compatible)
        case allowLongMessages(on: Bool)
        case adaptiveTiming(on: Bool)
        case canAutoFormat(on: Bool)
        case canReceiveArbitration(id: UInt32)
        case connect
        case describeProtocolNumeric
        case describeProtocolTextual
        case dummy
        case echo(on: Bool)
        case showHeaders(on: Bool)
        case identify
        case version1
        case version2
        case linefeed(on: Bool)
        case readVoltage
        case reset
        case spaces(on: Bool)
        case setHeader(id: UInt32)
        case setProtocol(p: UDS.BusProtocol)
        case setTimeout(UInt8)

        // extended (STN-compatible)
        case stnCanSegmentationReceive(on: Bool)
        case stnCanSegmentationTransmit(on: Bool)
        case stnCanSegmentationTimeouts(flowControl: UInt8, consecutiveFrame: UInt8)
        case stnCanTransmitAnnounce(header: UDS.Header? = nil, count: Int)
        case stnDeviceIdentify
        case stnExtendedIdentify
        case stnIdentify
        case stnProtocolTimeout(ms: UInt16)
        case stnSerialNumber

        // extended (UniCarScan-compatible)
        case unicarsIdentify

        // internal / meta (for probing etc.)
        case probeAutoSegmentation
        case probeFullFrameNoResponse
        case probeSmallFrameNoResponse

        // UDS
        case data(bytes: [UInt8])
    }
}
