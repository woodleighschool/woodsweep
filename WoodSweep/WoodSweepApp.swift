import Darwin
import SwiftUI

@main
enum WoodSweepMain {
    @MainActor
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "configure" {
            arguments.removeFirst()
            let status = await ConfigurationCommand.live.run(
                arguments: arguments
            )
            Darwin.exit(status)
        }

        WoodSweepApp.main()
    }
}

struct WoodSweepApp: App {
    var body: some Scene {
        WindowGroup {
            Text("WoodSweep")
                .padding()
        }
        .windowResizability(.contentSize)
    }
}
