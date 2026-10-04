import CompilerBackend
import CompilerCore
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
    case let .unknownOption(option):
        print("Unknown option: \(option)")
    case let .incompatibleStdlibOptions(message):
        print(message)
    case .stdlibOnlyRequiresLibraryEmit:
        print("--stdlib-only requires --emit library")
    }
}

let args = Array(ProcessInfo.processInfo.arguments.dropFirst())

do {
    let parsedOptions = try CLIParser.parse(args: args)
    if CompilerOptions.shouldUseDefaultStdlib(
        allowDefaultStdlibLibrary: parsedOptions.allowDefaultStdlibLibrary,
        includeStdlib: parsedOptions.includeStdlib,
        stdlibOnly: parsedOptions.stdlibOnly,
        stdlibLibraryPath: parsedOptions.stdlibLibraryPath,
        emit: parsedOptions.emit
    ) {
        do {
            CompilerOptions.defaultStdlibLibraryPath = try StdlibArtifactCache.resolveOrBuild(
                target: parsedOptions.target
            )
        } catch {
            let message = "KSWIFTK-LIB-0023: Cannot prepare the default bundled stdlib artifact: \(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(1)
        }
    }

    let options = try CLIParser.parse(args: args)
    let driver = CompilerDriver(backendPhases: makeBackendPhases)
    let exitCode = driver.run(options: options)
    exit(Int32(exitCode))
} catch let error as CLIParseError {
    if error == .usageRequested {
        printUsage()
        exit(0)
    }
    printCLIError(error)
    printUsage()
    exit(1)
} catch {
    print("Compiler internal error: \(error)")
    exit(1)
}
