import CompilerBackend
import CompilerCore
import Foundation

private final class CLIBackendPhaseBox: @unchecked Sendable {
    let phases: [CompilerPhase]

    init(_ phases: [CompilerPhase]) {
        self.phases = phases
    }
}

final class CLICompilerService: @unchecked Sendable {
    static let shared = CLICompilerService()

    private let lock = NSLock()
    private let driver: CompilerDriver

    private init() {
        KklibBatchSession.isEnabled = true
        let phaseBox = CLIBackendPhaseBox(makeBackendPhases(keepLLVMContextAlive: true))
        driver = CompilerDriver(
            backendPhases: { phaseBox.phases },
            backendPrefetch: { prefetchBackendLinkInputs(for: $0) }
        )
    }

    func run(args: [String]) -> Int32 {
        lock.lock()
        defer { lock.unlock() }

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
                    return 1
                }
            }

            let options = try CLIParser.parse(args: args)
            IncrementalCompilationCache.environmentFingerprintProvider = { options in
                incrementalEnvironmentFingerprint(for: options)
            }
            return Int32(driver.run(options: options))
        } catch let error as CLIParseError {
            if error == .usageRequested {
                printUsage()
                return 0
            }
            printCLIError(error)
            printUsage()
            return 1
        } catch {
            print("Compiler internal error: \(error)")
            return 1
        }
    }
}
