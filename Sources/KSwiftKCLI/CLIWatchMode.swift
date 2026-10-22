import Foundation
import CompilerCore

enum CLIWatchMode {
    private static let pollInterval: TimeInterval = 0.1

    static func run(args: [String]) -> Int32 {
        let compileArguments = args.filter { $0 != "--watch" }
        do {
            let options = try CLIParser.parse(args: compileArguments)
            let watchedPaths = options.inputs.map {
                URL(fileURLWithPath: $0, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL.path
            }
            let effectiveArguments = enablingIncrementalCompilationIfSupported(
                compileArguments,
                emit: options.emit
            )
            var signatures = fileSignatures(paths: watchedPaths)
            var lastExitCode = CLIApplication.runCompilation(args: effectiveArguments)
            print("Watching \(watchedPaths.count) input file(s). Press Ctrl-C to stop.")

            while true {
                Thread.sleep(forTimeInterval: pollInterval)
                let current = fileSignatures(paths: watchedPaths)
                guard current != signatures else { continue }
                signatures = current
                lastExitCode = CLIApplication.runCompilation(args: effectiveArguments)
            }
            return lastExitCode
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

    static func enablingIncrementalCompilationIfSupported(_ args: [String], emit: EmitMode) -> [String] {
        guard !emit.isJVM else { return args }
        let explicitlyConfigured = args.contains("--incremental")
            || args.contains("--incremental-cache")
            || args.contains("--no-incremental")
            || hasFrontendFlag("incremental", in: args)
            || hasFrontendFlag("no-incremental", in: args)
        return explicitlyConfigured ? args : args + ["--incremental"]
    }

    private static func hasFrontendFlag(_ expected: String, in args: [String]) -> Bool {
        guard args.count > 1 else { return false }
        for index in 0..<(args.count - 1) where args[index] == "-Xfrontend" {
            if args[index + 1] == expected { return true }
        }
        return false
    }

    private static func fileSignatures(paths: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: paths.map { path in
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                return (path, "missing")
            }
            let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let inode = (attributes[.systemFileNumber] as? NSNumber)?.int64Value ?? -1
            return (path, "\(Int64(date * 1_000_000_000)):\(size):\(inode)")
        })
    }
}
