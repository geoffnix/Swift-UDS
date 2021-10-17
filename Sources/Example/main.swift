//
// (C) Dr. Michael 'Mickey' Lauer <mickey@vanille-media.de>
//
import Swift_UDS
import Swift_UDS_Adapter
import Swift_UDS_Session
import CornucopiaStreams
import Foundation

var url: URL!
var adapter: UDS.Adapter!
var handler: Handler = .init()

class Handler {
    
    init() {
        
        NotificationCenter.default.addObserver(forName: UDS.AdapterCanInitHardware, object: nil, queue: nil) { _ in
            
            // Reset the UART speed (necessary on macOS) after opening the stream
            if url.scheme == "tty" {
                print("fixing up UART")
                let fd = open(url.path, 0)
                var settings = termios()
                cfsetspeed(&settings, speed_t(B115200))
                tcsetattr(fd, TCSANOW, &settings)
                close(fd)
            }
        }

        NotificationCenter.default.addObserver(forName: UDS.AdapterDidUpdateState, object: nil, queue: nil) { _ in
            
            guard case let .connected(busProtocol) = adapter.state else { return }
            /*
            let concurrency = 10
            for i in 0...concurrency {
                Task.detached(priority: nil) {
                    let message = UDS.Message(id: 0x7E0, reply: 0x7E8, bytes: [0x09, 0x02])
                    let response = try await adapter.sendUDS(message)
                    print("response: \(response)")
                }
            }
            */
            let pipeline = UDS.Pipeline(adapter: adapter)
            #if true
            let session = UDS.DiagnosticSession(with: 0x7E0, replyAddress: 0x7E8, via: pipeline)

            Task.detached {
                do {
                    let result = try await session.start(type: .programming)
                    print("start programming: \(result)")
                    let result2 = try await session.communicationControl(.enableRxAndDisableTx, messages: .normalCommunicationMessages)
                    print("disable message: \(result2)")
                } catch {
                    print("error: \(error)")
                }
            }
            #else

            let session = UDS.OBD2Session(via: pipeline)
            
            Task.detached {
                do {
                    let result = try await session.readString(service: .vehicleInformation(pid: UDS.VehicleInformationType.exhaustRegulationOrTypeApprovalNumber))
                    print("Response: '\(result)'")
                    
                } catch {
                    print("error: \(error)")
                }
            }
            #endif
        }
    }
}

func die(_ message: String? = nil) -> Never {
    guard let message = message else {
        print("""
              
              Usage: ./uds <stream-url-to-adapter>
              """)
        Foundation.exit(-1)
    }

    print("Error: \(message)")
    Foundation.exit(-1)
}

func main() async {

    let arguments = CommandLine.arguments
    guard arguments.count == 2 else { die() }
    url = URL(string: arguments[1]) ?? URL(string: "none://")!
    if url.scheme == "none" { die() }
    
    print("Connecting to \(url!)…")

    do {
        let streams = try await Stream.CC_getStreamPair(to: url, timeout: 3)
        adapter = UDS.GenericSerialAdapter(inputStream: streams.0, outputStream: streams.1)
        adapter.connect(via: .auto)
    } catch {
        print("error: \(error)")
    }
    try? await Task.sleep(nanoseconds: 20 * 1000000000)
    print("async main function exiting")
}

Task.detached { await main() }
let loop = RunLoop.current
while loop.run(mode: .default, before: Date.distantFuture) {
    loop.run()
}
