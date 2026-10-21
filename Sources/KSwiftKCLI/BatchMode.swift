import CompilerBackend
import CompilerCore
import Foundation

/// `kswiftc --batch <manifest>`: compiles many cases in one process so the
/// fixed `.kklib` import cost (process start, stdlib artifact resolution,
/// compact-index decode) is paid once instead of per case.
///
/// Manifest: one case per line, tab-separated —
/// `<stdout-file>\t<stderr-file>\t<exit-code-file>\t<kswiftc arg>...`.
/// Each case's stdout/stderr (including child processes such as the linker)
/// are redirected to the given files and its exit code is written to the
/// exit-code file. Only the decoded kklib index is shared between cases.
enum BatchMode {
    static func run(manifestPath: String) -> Int32 {
        guard let text = try? String(contentsOfFile: manifestPath, encoding: .utf8) else {
            FileHandle.standardError.write(Data("Cannot read batch manifest: \(manifestPath)\n".utf8))
            return 1
        }
        KklibBatchSession.isEnabled = true
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        defer {
            dup2(savedOut, STDOUT_FILENO)
            dup2(savedErr, STDERR_FILENO)
            close(savedOut)
            close(savedErr)
        }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { continue }
            let exitCode = withRedirectedOutput(stdout: fields[0], stderr: fields[1]) {
                compileOne(args: Array(fields.dropFirst(3)))
            }
            try? "\(exitCode)\n".write(toFile: fields[2], atomically: true, encoding: .utf8)
        }
        return 0
    }

    private static func withRedirectedOutput(stdout: String, stderr: String, _ body: () -> Int32) -> Int32 {
        fflush(Foundation.stdout)
        fflush(Foundation.stderr)
        let outFD = open(stdout, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        let errFD = open(stderr, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        if outFD >= 0 { dup2(outFD, STDOUT_FILENO) }
        if errFD >= 0 { dup2(errFD, STDERR_FILENO) }
        let code = body()
        fflush(Foundation.stdout)
        fflush(Foundation.stderr)
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        for fd in [outFD, errFD, savedOut, savedErr] where fd >= 0 { close(fd) }
        return code
    }

    private static func compileOne(args: [String]) -> Int32 {
        do {
            let parsed = try CLIParser.parse(args: args)
            if CompilerOptions.shouldUseDefaultStdlib(
                allowDefaultStdlibLibrary: parsed.allowDefaultStdlibLibrary,
                includeStdlib: parsed.includeStdlib,
                stdlibOnly: parsed.stdlibOnly,
                stdlibLibraryPath: parsed.stdlibLibraryPath,
                emit: parsed.emit
            ) {
                do {
                    CompilerOptions.defaultStdlibLibraryPath = try StdlibArtifactCache.resolveOrBuild(target: parsed.target)
                } catch {
                    FileHandle.standardError.write(
                        Data("KSWIFTK-LIB-0023: Cannot prepare the default bundled stdlib artifact: \(error)\n".utf8)
                    )
                    return 1
                }
            }
            let options = try CLIParser.parse(args: args)
            IncrementalCompilationCache.environmentFingerprintProvider = { options in
                incrementalEnvironmentFingerprint(for: options)
            }
            return Int32(CompilerDriver(backendPhases: makeBackendPhases).run(options: options))
        } catch let error as CLIParseError {
            if error == .usageRequested { printUsage(); return 0 }
            printCLIError(error)
            printUsage()
            return 1
        } catch {
            print("Compiler internal error: \(error)")
            return 1
        }
    }
}
