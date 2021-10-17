//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Foundation

extension String {
    
    var uds_localized: String { NSLocalizedString(self, bundle: Bundle.module, comment: "") }
}
