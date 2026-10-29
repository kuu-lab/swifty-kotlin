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
    /// written to a per-`LinkPhase` private temporary directory. Because every compilation
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

    private let session: LLVMBackendSession?

    init(session: LLVMBackendSession? = nil) { self.session = session }

    func run(_ ctx: CompilationContext) throws {
        guard ctx.options.emit == .executable else { return }
        // The wasm backend emits the final module itself; there is no host
        // object link step.
        guard !ctx.options.target.isWasm else { return }
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
        guard let entry = resolveEntrySymbol(
            kir: kir,
            ast: ctx.ast,
            bindings: ctx.sema?.bindings,
            interner: ctx.interner,
            moduleName: ctx.options.moduleName,
            symbols: ctx.sema?.symbols,
            fileFacadeNamesByFileID: CodegenSymbolSupport.fileFacadeNames(from: ctx.ast),
            entryPointFQName: ctx.options.entryPointFQName,
            types: ctx.sema?.types
        ) else {
            ctx.diagnostics.error(
                "KSWIFTK-LINK-0002",
                "No entry point '\(ctx.options.entryPointFQName ?? "main")' function found for executable emission.",
                range: nil
            )
            throw CompilerPipelineError.outputUnavailable
        }
        try CodegenCriticalSection.withLinuxExecutableToolchainLock(target: ctx.options.target) {
            try performLink(objectPath: objectPath, entrySymbol: entry.symbol, takesArguments: entry.takesArguments, ctx: ctx)
        }
    }

    private func performLink(objectPath: String, entrySymbol: String, takesArguments: Bool, ctx: CompilationContext) throws {
        let libraryInputs = withSubPhaseTiming("libraryObjects", timer: ctx.phaseTimer) {
            discoverLibraryLinkInputs(
                searchPaths: ctx.options.effectiveLibrarySearchPaths,
                target: ctx.options.target
            )
        }
        do {
            let runtimeObjects: [String]
            let linkerCacheDirectory: URL
            if libraryInputs.includesRuntime {
                runtimeObjects = []
                linkerCacheDirectory = CodegenRuntimeSupport.runtimeLinkerCacheDirectory()
            } else {
                let runtimeInputs = try withSubPhaseTiming("runtimeObjects", timer: ctx.phaseTimer) {
                    try RuntimeLinkInputPrefetch.shared.take(target: ctx.options.target, configuration: .release)
                        ?? CodegenRuntimeSupport.runtimeLinkInputs(
                            target: ctx.options.target,
                            configuration: .release
                        )
                }
                runtimeObjects = runtimeInputs.objects
                linkerCacheDirectory = runtimeInputs.linkerCacheDirectory
            }
            let entryWrapperObjectPath = try withSubPhaseTiming("entryWrapper", timer: ctx.phaseTimer) {
                try LLVMEntryPointObjectEmitter(target: ctx.options.target, takesArguments: takesArguments, phaseTimer: ctx.phaseTimer, session: session ?? LLVMBackendSession())
                    .emit(entrySymbol: entrySymbol)
            }
            let entryWrapperDirectoryPath = URL(fileURLWithPath: entryWrapperObjectPath)
                .deletingLastPathComponent()
                .path
            defer {
                try? FileManager.default.removeItem(atPath: entryWrapperDirectoryPath)
            }
            let autolinkStubPath = try withSubPhaseTiming("autolinkStub", timer: ctx.phaseTimer) {
                try emitSwiftAutolinkStubIfNeeded(target: ctx.options.target)
            }
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
                runtimeObjects: runtimeObjects, autoLinkedObjects: libraryInputs.objects
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
            if ctx.options.target.vendor == "apple", ctx.options.target.os == "macosx",
               !ctx.options.debugInfo,
               let plan = try? MacOSLinkerPlan.load(
                   swiftcPath: swiftcPath,
                   driverArguments: linkerDriverArgs(for: ctx.options.target),
                   cacheDirectory: linkerCacheDirectory,
                   phaseTimer: ctx.phaseTimer
               ) {
                var finalInputs = linkInputs
                // Force-loaded archives carry no user-referenced symbols, so a
                // successful partial link absorbs them; the final link then
                // drops the pairs instead of rescanning the archives.
                let forceLoadPaths = plan.forceLoadedPaths ?? []
                var dropForceLoads = false
                let prelinked = withSubPhaseTiming("prelinkedObjects", timer: ctx.phaseTimer) {
                    MacOSPrelinkedObjects.resolve(
                        inputs: Array(linkInputs.dropFirst(2)),
                        forceLoadPaths: forceLoadPaths,
                        cacheDirectory: linkerCacheDirectory
                            .appendingPathComponent("prelinked", isDirectory: true),
                        driver: plan.executable,
                        target: linkerTargetTriple(ctx.options.target),
                        phaseTimer: ctx.phaseTimer
                    )
                }
                if let prelinked {
                    finalInputs = [objectPath, entryWrapperObjectPath, prelinked]
                    dropForceLoads = plan.forceLoadedPaths != nil
                }
                _ = try CommandRunner.run(
                    executable: plan.executable,
                    arguments: plan.linkArguments(
                        inputs: finalInputs, output: ctx.options.outputPath,
                        libraryPaths: ctx.options.libraryPaths, libraries: ctx.options.linkLibraries,
                        droppingForceLoads: dropForceLoads
                    ),
                    phaseTimer: ctx.phaseTimer, subPhaseName: "Link/clang"
                )
                return
            }
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
        ast: ASTModule?,
        bindings: BindingTable?,
        interner: StringInterner,
        moduleName: String,
        symbols: SymbolTable?,
        fileFacadeNamesByFileID: [Int32: String],
        entryPointFQName: String?,
        types: TypeSystem?
    ) -> (symbol: String, takesArguments: Bool)? {
        guard let ast, let bindings,
              let symbol = ExecutableEntryPointSelector.firstFileLevelSymbol(
                ast: ast, bindings: bindings, arena: kir.arena, interner: interner,
                symbols: symbols, entryPointFQName: entryPointFQName
              ),
              let function = kir.arena.function(for: symbol)
        else { return nil }
        let takesArguments: Bool
        if function.params.isEmpty {
            takesArguments = false
        } else {
            guard function.params.count == 1, let types, let symbols,
                  let signature = symbols.functionSignature(for: symbol),
                  signature.receiverType == nil, signature.contextReceiverTypes.isEmpty,
                  signature.typeParameterSymbols.isEmpty, !signature.isSuspend,
                  case let .classType(arrayType) = types.kind(of: function.params[0].type),
                  arrayType.nullability == .nonNull,
                  symbols.symbol(arrayType.classSymbol)?.fqName.map(interner.resolve).joined(separator: ".") == "kotlin.Array",
                  arrayType.args.count == 1
            else { return nil }
            let elementType: TypeID
            switch arrayType.args[0] {
            case let .invariant(type), let .out(type): elementType = type
            case .in, .star: return nil
            }
            guard elementType == types.stringType else { return nil }
            takesArguments = true
        }
        return (
            CodegenSymbolSupport.cFunctionSymbol(
                for: function, interner: interner, moduleName: moduleName,
                symbols: symbols, fileFacadeNamesByFileID: fileFacadeNamesByFileID
            ),
            takesArguments
        )
    }

    func linkerDriverArgs(for target: TargetTriple) -> [String] {
        var args = ["-target", linkerTargetTriple(target)]
        if target.os.hasPrefix("linux") {
            // ELF dead stripping requires section-level garbage collection. Runtime functions
            // referenced by direct calls or generated dispatch tables remain reachable.
            args.append(contentsOf: [
                "-Xlinker", "--gc-sections",
                "-Xlinker", "-no-pie",
                "-parse-as-library",
            ])
        } else if target.vendor == "apple", target.os == "macosx" {
            // Keep functions reached through generated vtable/itable data while removing
            // unreferenced runtime atoms from the executable.
            args.append(contentsOf: ["-Xlinker", "-dead_strip"])
        }
        return args
    }

    func linkerTargetTriple(_ target: TargetTriple) -> String {
        if let version = target.osVersion, !version.isEmpty {
            return CodegenRuntimeSupport.targetTripleString(target)
        }
        if target.vendor == "apple", target.os == "macosx" {
            let minimumVersion = target.arch == "arm64" ? "11.0" : "10.9"
            return CodegenRuntimeSupport.targetTripleString(target) + minimumVersion
        }
        return CodegenRuntimeSupport.targetTripleString(target)
    }

    func discoverLibraryObjects(searchPaths: [String]) -> [String] {
        discoverLibraryLinkInputs(searchPaths: searchPaths, target: nil).objects
    }

    func discoverLibraryLinkInputs(
        searchPaths: [String],
        target: TargetTriple?
    ) -> (objects: [String], includesRuntime: Bool) {
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

        let hasPrelinkedStdlibCandidate = target.map { $0.vendor == "apple" && $0.os == "macosx" } == true
            && libraryDirs.contains { hasPrelinkedRuntimeObject(in: $0) }
        let runtimeFingerprint: String?
        let linkPlanKey: String?
        if hasPrelinkedStdlibCandidate, let target {
            runtimeFingerprint = try? CodegenRuntimeSupport.runtimeBuildCacheKey(
                target: target,
                configuration: .release
            )
            let swiftcPath = CommandRunner.resolveExecutable("swiftc", fallback: "/usr/bin/swiftc")
            linkPlanKey = MacOSLinkerPlan.cacheIdentity(
                swiftcPath: swiftcPath,
                driverArguments: linkerDriverArgs(for: target),
                environment: ProcessInfo.processInfo.environment
            )
        } else {
            runtimeFingerprint = nil
            linkPlanKey = nil
        }

        var collected: [String] = []
        var seen: Set<String> = []
        var includesRuntime = false
        for libraryDir in libraryDirs {
            // objectPaths already resolves symlinks and verifies containment
            // and regular-file status. Repeating that work for every returned
            // object made large imported libraries needlessly expensive.
            let libraryObjects = objectPaths(
                from: libraryDir,
                target: target,
                runtimeFingerprint: runtimeFingerprint,
                linkPlanKey: linkPlanKey
            )
            includesRuntime = includesRuntime || libraryObjects.includesRuntime
            for objectPath in libraryObjects.objects {
                if seen.insert(objectPath).inserted {
                    collected.append(objectPath)
                }
            }
        }
        return (collected, includesRuntime)
    }

    private func hasPrelinkedRuntimeObject(in libraryDir: String) -> Bool {
        let root = URL(fileURLWithPath: libraryDir).resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = root.appendingPathComponent("manifest.json")
        guard let safeManifest = containedRegularFileURL(manifestURL, under: root, fileManager: .default),
              let data = try? Data(contentsOf: safeManifest),
              let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data)
        else { return false }
        return manifest.libraryKind == "stdlib"
            && manifest.prelinkedObjectIncludesRuntime == true
            && manifest.prelinkedObject != nil
    }

    private func objectPaths(
        from libraryDir: String,
        target: TargetTriple?,
        runtimeFingerprint: String?,
        linkPlanKey: String?
    ) -> (objects: [String], includesRuntime: Bool) {
        let fileManager = FileManager.default
        let libraryRoot = URL(fileURLWithPath: libraryDir).resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = libraryRoot.appendingPathComponent("manifest.json")
        if let safeManifestURL = containedRegularFileURL(manifestURL, under: libraryRoot, fileManager: fileManager),
           let data = try? Data(contentsOf: safeManifestURL),
           let manifest = try? JSONDecoder().decode(LibraryManifest.self, from: data),
           let manifestObjects = manifest.objects
        {
            if manifest.libraryKind == "stdlib",
               manifest.stdlibManifestHash == BundledStdlib.manifestHash(),
               manifest.prelinkedObjectIncludesRuntime == true,
               manifest.prelinkedFormatVersion == 1,
               manifest.prelinkedCompilerVersion == CompilerBuildInfo.version,
               manifest.prelinkedRuntimeFingerprint.map({ !$0.isEmpty }) == true,
               runtimeFingerprint.map({ manifest.prelinkedRuntimeFingerprint == $0 }) ?? true,
               manifest.prelinkedLinkPlanKey.map({ !$0.isEmpty }) == true,
               manifest.prelinkedLinkPlanKey == linkPlanKey,
               target.map({ manifest.target == "\($0.arch)-\($0.vendor)-\($0.os)" }) ?? true,
               let relativePath = manifest.prelinkedObject,
               let url = containedRegularFileURL(
                   libraryRoot.appendingPathComponent(relativePath),
                   under: libraryRoot,
                   fileManager: fileManager
               )
            {
                return ([url.path], true)
            }
            let mapped = manifestObjects
                .filter { !$0.isEmpty }
                .compactMap {
                    containedRegularFileURL(
                        libraryRoot.appendingPathComponent($0),
                        under: libraryRoot,
                        fileManager: fileManager
                    )?.path
                }
            if !mapped.isEmpty {
                return (mapped, false)
            }
        }

        let objectsDir = URL(fileURLWithPath: libraryDir).appendingPathComponent("objects").path
        guard let entries = try? fileManager.contentsOfDirectory(atPath: objectsDir) else {
            return ([], false)
        }
        return (entries
            .filter { $0.hasSuffix(".o") }
            .sorted()
            .compactMap {
                containedRegularFileURL(
                    URL(fileURLWithPath: objectsDir).appendingPathComponent($0),
                    under: libraryRoot,
                    fileManager: fileManager
                )?.path
            }, false)
    }

    private func containedRegularFileURL(
        _ candidate: URL,
        under root: URL,
        fileManager: FileManager
    ) -> URL? {
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard resolved.path.hasPrefix(rootPath),
              let attributes = try? fileManager.attributesOfItem(atPath: resolved.path),
              attributes[.type] as? FileAttributeType == .typeRegular
        else {
            return nil
        }
        return resolved
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
