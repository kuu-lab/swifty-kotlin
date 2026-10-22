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
                CLICompilerService.shared.run(args: Array(fields.dropFirst(3)))
            }
            try? "\(exitCode)\n".write(toFile: fields[2], atomically: true, encoding: .utf8)
        }
        return 0
    }

    private static func withRedirectedOutput(stdout: String, stderr: String, _ body: () -> Int32) -> Int32 {
        fflush(nil)
        let outFD = open(stdout, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        let errFD = open(stderr, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
        let savedOut = dup(STDOUT_FILENO)
        let savedErr = dup(STDERR_FILENO)
        if outFD >= 0 { dup2(outFD, STDOUT_FILENO) }
        if errFD >= 0 { dup2(errFD, STDERR_FILENO) }
        let code = body()
        fflush(nil)
        dup2(savedOut, STDOUT_FILENO)
        dup2(savedErr, STDERR_FILENO)
        for fd in [outFD, errFD, savedOut, savedErr] where fd >= 0 { close(fd) }
        return code
    }

}
