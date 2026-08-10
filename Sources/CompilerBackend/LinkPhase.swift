import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CompilerCore

final class LinkPhase: CompilerPhase {
    static let name = "Link"

    /// Linux links emit a Swift autolink stub that pulls in runtime dependencies. The stub is
    /// written to a per-`LinkPhase` private temporary directory
    /// (`TMPDIR/kswiftk-link-stubs-<uid>-<pid>-<uuid>`, mode 0700). Because every compilation
    /// uses its own directory, parallel `kswiftc` processes and Swift test workers never share
    /// the same stub path. The complete link operation is still guarded by a per-target
    /// cross-process toolchain lock on Linux because concurrent `swiftc` invocations can
    /// interfere on self-hosted runners. The directory is created with `mkdir(0700)` and
    /// validated to be owned by the current user with no group/other permissions, so a local
    /// attacker cannot tamper with the build input.
    private static let linuxAutolinkStubContents = """
    import Dispatch
    import Foundation

    @inline(never)
    private func _kswiftkRuntimeAutolinkAnchor() {
        _ = NSLock()
        _ = DispatchQueue.global(qos: .default)
        _ = DispatchSemaphore(value: 0)
    }
    """

    private let stubLock = NSLock()
    private var stubDirectory: URL?

    init() {}

    func run(_ ctx: CompilationContext) throws {
        guard ctx.options.emit == .executable else { return }
        guard let objectPath = ctx.generatedObjectPath else {
            ctx.diagnostics.error(
                "KSWIFTK-LINK-0004",
                "Link phase expected a generated object file path, but none was recorded after codegen.",
                range: nil
            )
            throw CompilerPipelineError.outputUnavailable
        }
        guard FileManager.default.fileExists(atPath: objectPath) else {
            ctx.diagnostics.error(
                "KSWIFTK-LINK-0004",
                "Link phase expected object file at '\(objectPath)', but the file does not exist.",
                range: nil
            )
            throw CompilerPipelineError.outputUnavailable
        }
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available during link.")
        }
        guard let entrySymbol = resolveEntrySymbol(
            kir: kir,
            interner: ctx.interner,
            fileFacadeNamesByFileID: CodegenSymbolSupport.fileFacadeNames(from: ctx.ast)
        ) else {
            ctx.diagnostics.error(
                "KSWIFTK-LINK-0002",
                "No entry point 'main' function found for executable emission.",
                range: nil
            )
            throw CompilerPipelineError.outputUnavailable
        }
        try CodegenCriticalSection.withLinuxExecutableToolchainLock(target: ctx.options.target) {
            try performLink(objectPath: objectPath, entrySymbol: entrySymbol, ctx: ctx)
        }
    }

    private func performLink(objectPath: String, entrySymbol: String, ctx: CompilationContext) throws {
        let autoLinkedObjects = discoverLibraryObjects(searchPaths: ctx.options.effectiveLibrarySearchPaths)
        do {
            let runtimeObjects = try CodegenRuntimeSupport.runtimeObjectPaths(target: ctx.options.target)
            let entryWrapperObjectPath = try LLVMEntryPointObjectEmitter(target: ctx.options.target)
                .emit(entrySymbol: entrySymbol, outputPath: ctx.options.outputPath)
            let entryWrapperDirectoryPath = URL(fileURLWithPath: entryWrapperObjectPath)
                .deletingLastPathComponent()
                .path
            defer {
                try? FileManager.default.removeItem(atPath: entryWrapperDirectoryPath)
            }
            let autolinkStubPath = try emitSwiftAutolinkStubIfNeeded(target: ctx.options.target)
            var stubDirectoryPath: String?
            if let autolinkStubPath {
                stubDirectoryPath = URL(fileURLWithPath: autolinkStubPath).deletingLastPathComponent().path
            }
            defer {
                if let stubDirectoryPath {
                    try? FileManager.default.removeItem(atPath: stubDirectoryPath)
                }
            }
            let linkInputs = buildLinkInputs(
                objectPath: objectPath, entryWrapperObjectPath: entryWrapperObjectPath,
                runtimeObjects: runtimeObjects, autoLinkedObjects: autoLinkedObjects
            )
            var args = linkInputs
            if let autolinkStubPath {
                args.append(autolinkStubPath)
            }
            if ctx.options.debugInfo { args.append("-g") }
            args.append(contentsOf: ["-o", ctx.options.outputPath])
            args.append(contentsOf: linkerDriverArgs(for: ctx.options.target))
            ctx.options.libraryPaths.forEach { args.append("-L\($0)") }
            ctx.options.linkLibraries.forEach { args.append("-l\($0)") }
            let swiftcPath = CommandRunner.resolveExecutable("swiftc", fallback: "/usr/bin/swiftc")
            _ = try CommandRunner.run(
                executable: swiftcPath, arguments: args,
                phaseTimer: ctx.phaseTimer, subPhaseName: "Link/swiftc"
            )
        } catch let error as CommandRunnerError {
            ctx.diagnostics.error("KSWIFTK-LINK-0001", commandRunnerErrorMessage(error), range: nil)
            throw CompilerPipelineError.outputUnavailable
        } catch {
            ctx.diagnostics.error("KSWIFTK-LINK-0001", "Link step failed: \(error)", range: nil)
            throw CompilerPipelineError.outputUnavailable
        }
    }

    func emitSwiftAutolinkStubIfNeeded(target: TargetTriple) throws -> String? {
        guard target.os.hasPrefix("linux") else {
            return nil
        }

        stubLock.lock()
        defer { stubLock.unlock() }

        let stubDirectory = try secureStubDirectory()

        let targetKey = CodegenRuntimeSupport.stableFNV1a64Hex(CodegenRuntimeSupport.targetTripleString(target))
        let stubName = "runtime-autolink-\(targetKey).swift"
        let stubURL = stubDirectory.appendingPathComponent(stubName)
        let currentContents = try? String(contentsOf: stubURL, encoding: .utf8)
        if currentContents != Self.linuxAutolinkStubContents {
            try Self.linuxAutolinkStubContents.write(to: stubURL, atomically: true, encoding: .utf8)
        }
        return stubURL.path
    }

    private func secureStubDirectory() throws -> URL {
        if let cached = stubDirectory {
            return cached
        }

        let uid = getuid()
        let pid = getpid()
        let uuid = UUID().uuidString
        let stubDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("kswiftk-link-stubs-\(uid)-\(pid)-\(uuid)", isDirectory: true)
        let path = stubDirectory.path
        guard path.withCString({ mkdir($0, S_IRWXU) }) == 0 else {
            throw LinkPhaseStubError.systemCallFailed("mkdir", errno)
        }

        var info = stat()
        guard path.withCString({ lstat($0, &info) }) == 0 else {
            throw LinkPhaseStubError.systemCallFailed("lstat", errno)
        }
        guard (info.st_mode & S_IFMT) == S_IFDIR else {
            throw LinkPhaseStubError.insecurePath(path, "not a directory")
        }
        guard info.st_uid == uid else {
            throw LinkPhaseStubError.insecurePath(path, "unexpected owner")
        }
        guard (info.st_mode & (S_IRWXG | S_IRWXO)) == 0 else {
            throw LinkPhaseStubError.insecurePath(path, "group/other permissions are not allowed")
        }

        self.stubDirectory = stubDirectory
        return stubDirectory
    }

    private func buildLinkInputs(
        objectPath: String,
        entryWrapperObjectPath: String,
        runtimeObjects: [String],
        autoLinkedObjects: [String]
    ) -> [String] {
        var linkInputs: [String] = [objectPath, entryWrapperObjectPath]
        for obj in runtimeObjects where !linkInputs.contains(obj) {
            linkInputs.append(obj)
        }
        for obj in autoLinkedObjects where !linkInputs.contains(obj) {
            linkInputs.append(obj)
        }
        return linkInputs
    }

    private func commandRunnerErrorMessage(_ error: CommandRunnerError) -> String {
        switch error {
        case let .launchFailed(reason):
            return "Failed to launch linker: \(reason)"
        case let .nonZeroExit(result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let output = "STDOUT: \(stdout)\nSTDERR: \(stderr)"
            return "Linker failed with exit code \(result.exitCode):\n\(output)"
        case let .timedOut(reason):
            return "Linker timed out: \(reason)"
        }
    }

    private func resolveEntrySymbol(
        kir: KIRModule,
        interner: StringInterner,
        fileFacadeNamesByFileID: [Int32: String]
    ) -> String? {
        let knownNames = KnownCompilerNames(interner: interner)
        let mainNameResolved = interner.resolve(knownNames.main)
        for decl in kir.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            // Compare interned IDs first; fall back to the resolved string so
            // an entry point is found even if `main` was interned on a
            // different code path and received a distinct `InternedString`.
            if function.name == knownNames.main
                || (!mainNameResolved.isEmpty && interner.resolve(function.name) == mainNameResolved) {
                return CodegenSymbolSupport.cFunctionSymbol(
                    for: function,
                    interner: interner,
                    fileFacadeNamesByFileID: fileFacadeNamesByFileID
                )
            }
        }
        return nil
    }

    func linkerDriverArgs(for target: TargetTriple) -> [String] {
        var args = ["-target", linkerTargetTriple(target)]
        if target.os.hasPrefix("linux") {
            args.append(contentsOf: ["-Xlinker", "-no-pie", "-parse-as-library"])
        }
        return args
    }

    private func linkerTargetTriple(_ target: TargetTriple) -> String {
        if let version = target.osVersion, !version.isEmpty {
            return CodegenRuntimeSupport.targetTripleString(target)
        }
        if target.vendor == "apple", target.os == "macosx" {
            let minimumVersion = target.arch == "arm64" ? "11.0" : "10.9"
            return CodegenRuntimeSupport.targetTripleString(target) + minimumVersion
        }
        return CodegenRuntimeSupport.targetTripleString(target)
    }

    private func discoverLibraryObjects(searchPaths: [String]) -> [String] {
        let fileManager = FileManager.default
        var libraryDirs: [String] = []
        var libraryDirSeen: Set<String> = []
        for rawPath in searchPaths {
            let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            if path.hasSuffix(".kklib") {
                if libraryDirSeen.insert(path).inserted {
                    libraryDirs.append(path)
                }
                continue
            }
            guard let entries = try? fileManager.contentsOfDirectory(atPath: path) else {
                continue
            }
            for entry in entries where entry.hasSuffix(".kklib") {
                let fullPath = URL(fileURLWithPath: path).appendingPathComponent(entry).standardizedFileURL.path
                if libraryDirSeen.insert(fullPath).inserted {
                    libraryDirs.append(fullPath)
                }
            }
        }

        var collected: [String] = []
        var seen: Set<String> = []
        for libraryDir in libraryDirs {
            for objectPath in objectPaths(from: libraryDir) {
                let absolutePath = URL(fileURLWithPath: objectPath).standardizedFileURL.path
                guard fileManager.fileExists(atPath: absolutePath) else {
                    continue
                }
                if seen.insert(absolutePath).inserted {
                    collected.append(absolutePath)
                }
            }
        }
        return collected
    }

    private func objectPaths(from libraryDir: String) -> [String] {
        let fileManager = FileManager.default
        let manifestPath = URL(fileURLWithPath: libraryDir).appendingPathComponent("manifest.json").path
        if let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
           let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data),
           let manifestObjects = manifest.objects
        {
            let libraryDirNormalized = URL(fileURLWithPath: libraryDir).standardized.path
            let mapped = manifestObjects
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: libraryDir).appendingPathComponent($0).standardized.path }
                .filter { $0.hasPrefix(libraryDirNormalized + "/") }
            if !mapped.isEmpty {
                return mapped
            }
        }

        let objectsDir = URL(fileURLWithPath: libraryDir).appendingPathComponent("objects").path
        guard let entries = try? fileManager.contentsOfDirectory(atPath: objectsDir) else {
            return []
        }
        return entries
            .filter { $0.hasSuffix(".o") }
            .sorted()
            .map { URL(fileURLWithPath: objectsDir).appendingPathComponent($0).path }
    }
}

private enum LinkPhaseStubError: Error, CustomStringConvertible {
    case systemCallFailed(String, Int32)
    case insecurePath(String, String)

    var description: String {
        switch self {
        case let .systemCallFailed(operation, errorCode):
            return "\(operation) failed: \(String(cString: strerror(errorCode)))"
        case let .insecurePath(path, reason):
            return "insecure path '\(path)': \(reason)"
        }
    }
}
