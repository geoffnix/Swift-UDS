//
// Swift-UDS. (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
extension String: UDS.ConstructableViaMessage {

    public init(message: UDS.Message) {
        self = message.bytes.map { String(format: "%c", $0.CC_isASCII ? $0 : 0x2E) }.joined()
    }
}
