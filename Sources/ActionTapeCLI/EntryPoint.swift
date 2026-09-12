import ActionTapeCLIKit
import Darwin
import Dispatch

@main
struct ActionTapeCommand {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let task = Task { await CLIExecutor.execute(arguments: arguments) }
        signal(SIGINT, SIG_IGN)
        let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
        // Dispatch calls this on a global queue. Prevent Swift 6 from inheriting
        // main()'s actor isolation and trapping when Ctrl-C arrives.
        interrupt.setEventHandler { @Sendable in task.cancel() }
        interrupt.resume()
        let code = await task.value
        interrupt.cancel()
        Darwin.exit(code)
    }
}
