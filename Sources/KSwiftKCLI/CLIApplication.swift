import Foundation

func printUsage() {
    print(CLIParser.usageText)
}

func printCLIError(_ error: CLIParseError) {
    switch error {
    case .usageRequested, .noInputFiles:
        break
    case let .missingValue(option):
        print("Missing value for option: \(option)")
    case let .unsupportedEmitMode(value):
        print("Unsupported emit mode: \(value)")
    case let .unsupportedOptimizationLevel(value):
        print("Unsupported optimization level: \(value)")
    case let .invalidTargetTriple(value):
        print("Invalid target triple: \(value)")
    case let .unsupportedDiagnosticsFormat(value):
        print("Unsupported diagnostics format: \(value)")
    case let .unsupportedNameBasedDestructuringMode(value):
        print("Unsupported name-based destructuring mode: \(value)")
    case let .unknownOption(option):
        print("Unknown option: \(option)")
    case let .incompatibleStdlibOptions(message):
        print(message)
    case .stdlibOnlyRequiresLibraryEmit:
        print("--stdlib-only requires --emit library")
    case let .unsupportedStdlibProfile(value):
        print("Unsupported stdlib profile: \(value) (expected full or minimal)")
    }
}

enum CLIApplication {
    static func run(args: [String]) -> Int32 {
        if args == ["--daemon"] {
            return CompileDaemonServer().runForeground()
        }
        if args.count == 2, args[0] == "--batch" {
            return BatchMode.run(manifestPath: args[1])
        }
        if args.contains("--watch") {
            return CLIWatchMode.run(args: args)
        }
        return runCompilation(args: args)
    }

    static func runCompilation(args: [String], socketPath: String? = nil) -> Int32 {
        let response: CompileDaemonResponse?
        if let socketPath {
            response = CompileDaemonClient.request(arguments: args, socketPath: socketPath)
        } else {
            response = CompileDaemonClient.request(arguments: args)
        }
        if let response {
            FileHandle.standardOutput.write(Data(response.stdout.utf8))
            FileHandle.standardError.write(Data(response.stderr.utf8))
            return response.exitCode
        }
        return CLICompilerService.shared.run(args: args)
    }
}
