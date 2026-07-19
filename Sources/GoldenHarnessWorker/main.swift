import Foundation
import GoldenHarnessSupport

@main
struct GoldenHarnessWorkerMain {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            if arguments.first == "--batch" {
                try runBatch(arguments: arguments)
            } else {
                try runSingle(arguments: arguments)
            }
        } catch {
            let message = String(describing: error) + "\n"
            FileHandle.standardError.write(Data(message.utf8))
            Foundation.exit(1)
        }
    }

    private static func runSingle(arguments: [String]) throws {
        guard arguments.count == 2 else {
            throw WorkerError.invalidArguments
        }
        let output = try GoldenHarness.render(
            suiteName: arguments[0],
            sourcePath: arguments[1]
        )
        FileHandle.standardOutput.write(Data(output.utf8))
    }

    private static func runBatch(arguments: [String]) throws {
        guard arguments.count >= 3 else {
            throw WorkerError.invalidArguments
        }
        let suiteName = arguments[1]
        let results = arguments.dropFirst(2).map { sourcePath in
            do {
                return GoldenHarnessBatchResult(
                    sourcePath: sourcePath,
                    output: try GoldenHarness.render(
                        suiteName: suiteName,
                        sourcePath: sourcePath
                    ),
                    errorDescription: nil
                )
            } catch {
                return GoldenHarnessBatchResult(
                    sourcePath: sourcePath,
                    output: nil,
                    errorDescription: String(describing: error)
                )
            }
        }
        FileHandle.standardOutput.write(try JSONEncoder().encode(results))
    }
}

enum WorkerError: Error, CustomStringConvertible {
    case invalidArguments

    var description: String {
        switch self {
        case .invalidArguments:
            """
            usage:
              GoldenHarnessWorker <suite> <sourcePath>
              GoldenHarnessWorker --batch <suite> <sourcePath>...
            """
        }
    }
}
