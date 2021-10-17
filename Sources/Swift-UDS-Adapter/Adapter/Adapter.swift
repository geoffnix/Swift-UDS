//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Foundation
import Swift_UDS

extension UDS {

    /// The adapter information
    public struct AdapterInfo: Equatable {
        public let model: String
        public let ic: String
        public let vendor: String
        public let serialNumber: String
        public let firmwareVersion: String
    }

    /// The adapter state
    public enum AdapterState: Equatable {
        case created                        // => searching
        case searching                      // => notFound || initializing
        case notFound                       // (terminal)
        case initializing                   // => error || configuring
        case configuring(AdapterInfo)       // => error || connected || unsupportedProtocol
        case connected(BusProtocol)         // => gone
        case unsupportedProtocol            // => gone
        case gone                           // (terminal)
        
        public var isConnected: Bool {
            if case .connected(_) = self {
                return true
            } else {
                return false
            }
        }
    }
    
    /// Sent after a change of the adapter state.
    public static let AdapterDidUpdateState: Notification.Name = .init("AdapterDidUpdateState")
    /// Sent after opening the hardware input. May be used for further hardware configuration.
    public static let AdapterCanInitHardware: Notification.Name = .init("AdapterCanInitHardware")
}

/// The adapter API
public protocol _UDSAdapter {

    /// Details about the adapter. Not available in adapter states.
    var info: UDS.AdapterInfo? { get }
    /// The current state of the adapter.
    var state: UDS.AdapterState { get }
    /// The MTU for data transfer. Especially important for firmware upgrade which relies on large (4K) ISO-TP segmented UDS messages.
    var mtu: Int { get }

    /// Connect to the vehicle using the specified `busProtocol`. If you're not sure, use `.auto` for auto netgotiation.
    func connect(via busProtocol: UDS.BusProtocol)
    /// Send a message and return the result.
    func sendUDS(_ message: UDS.Message) async throws -> UDS.Message
    /// Safely shutdown the adapter.
    func shutdown()
}

extension UDS {
    
    public typealias Adapter = _UDSAdapter
    
}
