//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import CornucopiaCore
import Foundation
import Swift_UDS

private let logger = Cornucopia.Core.Logger()

extension UDS {
    
    public class BaseAdapter: Adapter {

        public var info: UDS.AdapterInfo?
        public var state: UDS.AdapterState = .created {
            didSet {
                logger.debug("AdapterState now \(self.state)")
                NotificationCenter.default.post(name: UDS.AdapterDidUpdateState, object: self)
                self.didUpdateState()
            }
        }
        public var mtu: Int = 0
        public var numberOfHeaderCharacters: Int = 0

        public func connect(via busProtocol: UDS.BusProtocol)                   { fatalError("not implemented in BaseAdapter") }
        public func sendUDS(_ message: UDS.Message) async throws -> UDS.Message { fatalError("not implemented in BaseAdapter") }
        public func shutdown()                                                  { fatalError("not implemented in BaseAdapter") }
        
        public func didUpdateState() { }
    }
}

internal extension UDS.BaseAdapter {
    
    func updateState(_ next: UDS.AdapterState) {
        guard self.state != next else {
            return
        }
        if case let .connected(busProtocol) = next {
            self.numberOfHeaderCharacters = busProtocol.numberOfHeaderCharacters
        }
        self.state = next
    }
}
