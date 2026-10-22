import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The `KSWIFTK_STDLIB_CACHE_DIR` override of the user's standard caches
/// directory is intended for sandboxes and test isolation. Each target, bundled-source hash, and
/// compiler fingerprint gets its own cache path, so another worktree cannot
/// replace an artifact after a compiler has resolved its path. An advisory
/// lock prevents parallel first launches for the same cache key from
/// publishing a partial `.kklib`; each build stages under a unique
/// `.building-*` path and only a fully validated artifact is moved into place.
public enum StdlibArtifactCache {
    public enum Error: Swift.Error, CustomStringConvertible {
        case explicitArtifactInvalid(path: String, reason: String)
        case cacheDirectoryUnavailable
        case lockFileCreateFailed(path: String, errno: Int32)
        case lockFailed(path: String, errno: Int32)
        case artifactInvalid(path: String, reason: String)
        case buildFailed(String)

        public var description: String {
            switch self {
            case let .explicitArtifactInvalid(path, reason):
                return "KSWIFTK_STDLIB_LIBRARY '\(path)' is not a compatible stdlib artifact: \(reason)"
            case .cacheDirectoryUnavailable:
                return "The user's standard caches directory is unavailable"
            case let .lockFileCreateFailed(path, errno):
                return "Could not create stdlib cache lock '\(path)': errno \(errno)"
            case let .lockFailed(path, errno):
                return "Could not acquire stdlib cache lock '\(path)': errno \(errno)"
            case let .artifactInvalid(path, reason):
                return "Generated stdlib artifact '\(path)' is invalid: \(reason)"
            case let .buildFailed(message):
                return "stdlib-only artifact build failed: \(message)"
            }
        }
    }

    private static let artifactFileName = "KSwiftKStdlib.kklib"
    private static let artifactLayoutVersion = "prelinked-runtime-v1"
    private static let kotlinLanguageVersion = "2.4.20"
    private static let compilerVersion = CompilerBuildInfo.version

    public static func resolveOrBuild(target: TargetTriple) throws -> String {
        let fileManager = FileManager.default
        let environment = ProcessInfo.processInfo.environment

        if let explicit = environment["KSWIFTK_STDLIB_LIBRARY"], !explicit.isEmpty {
            switch validateArtifact(at: explicit, target: target) {
            case .valid:
                return normalizedPath(explicit)
            case let .invalid(reason):
                throw Error.explicitArtifactInvalid(path: explicit, reason: reason)
            }
        }

        for candidate in packagedArtifactCandidates() {
            guard fileManager.fileExists(atPath: candidate) else { continue }
            if case .valid = validateArtifact(at: candidate, target: target) {
                return normalizedPath(candidate)
            }
        }

        let cacheDirectory: URL
        if let override = environment["KSWIFTK_STDLIB_CACHE_DIR"], !override.isEmpty {
            cacheDirectory = URL(fileURLWithPath: override)
        } else {
            guard let cachesURL = fileManager.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first else {
                throw Error.cacheDirectoryUnavailable
            }
            cacheDirectory = cachesURL
        }

        return try resolveOrBuildCached(
            target: target,
            cacheDirectory: cacheDirectory,
            fileManager: fileManager
        ) { outputBase in
            try StdlibArtifactBuilder.build(
                outputBase: outputBase,
                target: target,
                includeRuntimePrelink: true
            )
        }
    }

    /// The cache path
    /// includes the bundled-source hash and compiler fingerprint, so each
    /// distinct build has an independent artifact that remains stable after
    /// this method returns. The builder receives a private output-base path
    /// and must return the `.kklib` directory it produced there; it is injected
    /// so tests can exercise the locking, staging, and recovery paths without
    /// paying for a real stdlib build.
    ///
    /// Recovery contract: a build that is killed or fails midway can only
    /// leave its own uniquely-named staging tree behind — never a partially
    /// published `KSwiftKStdlib.kklib` — and a cached artifact that fails
    /// validation (e.g. inline-KIR blobs deleted out from under it) is
    /// rebuilt instead of being handed to a compile that would fail later
    /// with KSWIFTK-LIB-0019 or missing link symbols.
    static func resolveOrBuildCached(
        target: TargetTriple,
        cacheDirectory: URL,
        fileManager: FileManager = .default,
        compilerFingerprint: String? = nil,
        builder: (_ outputBase: String) throws -> String
    ) throws -> String {
        let currentFingerprint = compilerFingerprint ?? currentCompilerFingerprint()
        let cacheFingerprint = currentFingerprint ?? "unavailable-\(UUID().uuidString)"
        let artifactURL = cacheArtifactURL(
            for: target,
            cacheDirectory: cacheDirectory,
            stdlibManifestHash: BundledStdlib.manifestHash(),
            compilerFingerprint: cacheFingerprint
        )
        let artifactPath = artifactURL.path
        let lockPath = artifactPath + ".lock"
        try fileManager.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        return try withFileLock(at: lockPath) {
            if case .valid = validateArtifact(at: artifactPath, target: target) {
                return artifactPath
            }

            removeStaleStagingDirectories(artifactPath: artifactPath, fileManager: fileManager)

            // Stage each build under a per-attempt path: an interrupted build
            // leaves an inert partial tree that is never published, and no
            // other process ever shares or deletes this staging path.
            let buildingBase = artifactPath + ".building-\(getpid())-\(UUID().uuidString)"
            let buildingArtifactPath = buildingBase + ".kklib"

            let builtArtifactPath: String
            do {
                builtArtifactPath = try builder(buildingBase)
            } catch {
                try? fileManager.removeItem(atPath: buildingBase)
                try? fileManager.removeItem(atPath: buildingArtifactPath)
                throw Error.buildFailed(String(describing: error))
            }

            guard case .valid = validateArtifact(at: builtArtifactPath, target: target) else {
                let reason = validationReason(at: builtArtifactPath, target: target)
                try? fileManager.removeItem(atPath: buildingBase)
                try? fileManager.removeItem(atPath: builtArtifactPath)
                throw Error.artifactInvalid(
                    path: builtArtifactPath,
                    reason: reason
                )
            }

            // Publish only now that the replacement is complete: the previous
            // artifact stays in place until the swap so a failed rebuild never
            // leaves the cache empty.
            if fileManager.fileExists(atPath: artifactPath) {
                try? fileManager.removeItem(atPath: artifactPath)
            }
            do {
                try fileManager.moveItem(atPath: builtArtifactPath, toPath: artifactPath)
            } catch {
                // Unreachable while the lock holds, but a deleted or recreated
                // lock file can split the critical section and let another
                // builder publish first. Prefer whatever landed when it
                // validates instead of reporting a spurious failure.
                if case .valid = validateArtifact(at: artifactPath, target: target) {
                    try? fileManager.removeItem(atPath: buildingBase)
                    try? fileManager.removeItem(atPath: builtArtifactPath)
                    return artifactPath
                }
                try? fileManager.removeItem(atPath: buildingBase)
                try? fileManager.removeItem(atPath: builtArtifactPath)
                throw Error.buildFailed(
                    "could not publish the stdlib artifact: \(error.localizedDescription)"
                )
            }
            return artifactPath
        }
    }

    /// `KSWIFTK_STDLIB_LIBRARY` is handled separately because it is explicit
    /// and must fail loudly when it points at an incompatible artifact.
    public static func packagedArtifactCandidates(executablePath: String? = nil) -> [String] {
        var candidates: [String] = []

        func append(_ url: URL) {
            let path = url.standardizedFileURL.path
            if !candidates.contains(path) {
                candidates.append(path)
            }
        }

        let executableURL = executablePath.map { URL(fileURLWithPath: $0) } ?? resolvedExecutableURL()
        if let executableURL {
            let resolvedExecutable = executableURL.resolvingSymlinksInPath()
            let binDirectory = resolvedExecutable.deletingLastPathComponent()
            let prefixDirectory = binDirectory.deletingLastPathComponent()

            append(binDirectory.appendingPathComponent(artifactFileName))
            append(binDirectory.appendingPathComponent("stdlib", isDirectory: true)
                .appendingPathComponent(artifactFileName))
            append(binDirectory.appendingPathComponent("KSwiftK_CompilerCore.resources", isDirectory: true)
                .appendingPathComponent(artifactFileName))
            append(binDirectory.appendingPathComponent("KSwiftK_CompilerCore.bundle/Contents/Resources", isDirectory: true)
                .appendingPathComponent(artifactFileName))
            // Keep the target-only resource bundle spelling used by older
            // SwiftPM/Xcode layouts as a compatibility candidate.
            append(binDirectory.appendingPathComponent("CompilerCore_CompilerCore.resources", isDirectory: true)
                .appendingPathComponent(artifactFileName))
            append(prefixDirectory.appendingPathComponent("lib/kswiftk/stdlib", isDirectory: true)
                .appendingPathComponent(artifactFileName))
        }

        return candidates
    }

    private static func cacheArtifactURL(
        for target: TargetTriple,
        cacheDirectory: URL,
        stdlibManifestHash: String,
        compilerFingerprint: String
    ) -> URL {
        let targetKey = [target.arch, target.vendor, target.os, target.osVersion ?? "none"]
            .map { component in
                component.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "\\", with: "_")
            }
            .joined(separator: "-")
        let fingerprintKey = compilerFingerprint
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        return cacheDirectory
            .appendingPathComponent("kswiftk", isDirectory: true)
            .appendingPathComponent("stdlib", isDirectory: true)
            .appendingPathComponent(
                "\(kotlinLanguageVersion)-\(compilerVersion)-\(targetKey)-\(stdlibManifestHash)-\(artifactLayoutVersion)-\(fingerprintKey)",
                isDirectory: true
            )
            .appendingPathComponent(artifactFileName, isDirectory: true)
    }

    /// A leftover staging tree from a build interrupted more than this long
    /// ago can no longer be written by a live builder, so it is safe to
    /// reclaim. A successful build finishes in minutes; this is deliberately
    /// far above that.
    private static let staleStagingAge: TimeInterval = 3600

    /// Called while the cache lock is held, so only trees too old to belong to
    /// a still-running builder are reclaimed — anything newer is left alone.
    private static func removeStaleStagingDirectories(
        artifactPath: String,
        fileManager: FileManager
    ) {
        let parentPath = URL(fileURLWithPath: artifactPath).deletingLastPathComponent().path
        let prefix = artifactFileName + ".building"
        guard let entries = try? fileManager.contentsOfDirectory(atPath: parentPath) else { return }
        let cutoff = Date().addingTimeInterval(-staleStagingAge)
        for entry in entries where entry.hasPrefix(prefix) {
            let entryPath = parentPath + "/" + entry
            guard let attributes = try? fileManager.attributesOfItem(atPath: entryPath),
                  let modified = attributes[.modificationDate] as? Date,
                  modified < cutoff
            else { continue }
            try? fileManager.removeItem(atPath: entryPath)
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private enum ValidationResult {
        case valid
        case invalid(String)
    }

    private static func validationReason(at path: String, target: TargetTriple) -> String {
        if case let .invalid(reason) = validateArtifact(at: path, target: target) {
            return reason
        }
        return "unknown validation failure"
    }

    private static func validateArtifact(at path: String, target: TargetTriple) -> ValidationResult {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .invalid("artifact directory does not exist")
        }

        guard let manifestURL = CompilerFileSystem.containedURL(relativePath: "manifest.json", under: rootURL),
              CompilerFileSystem.isRegularFile(at: manifestURL, fileManager: fileManager)
        else {
            return .invalid("manifest.json is missing, not a regular file, or escapes the artifact")
        }
        guard let data = try? Data(contentsOf: manifestURL) else {
            return .invalid("manifest.json is missing")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let manifest = object as? [String: Any]
        else {
            return .invalid("manifest.json is not valid JSON")
        }

        guard let formatVersion = manifest["formatVersion"] as? Int,
              (formatVersion == 1 || formatVersion == 2)
        else {
            return .invalid("manifest formatVersion must be 1 or 2")
        }
        guard manifest["moduleName"] as? String == "KSwiftKStdlib" else {
            return .invalid("manifest moduleName must be KSwiftKStdlib")
        }
        guard manifest["libraryKind"] as? String == "stdlib" else {
            return .invalid("manifest libraryKind must be stdlib")
        }
        guard manifest["kotlinLanguageVersion"] as? String == kotlinLanguageVersion else {
            return .invalid("manifest kotlinLanguageVersion is incompatible")
        }
        guard manifest["compilerVersion"] as? String == compilerVersion else {
            return .invalid("manifest compilerVersion is incompatible")
        }

        let targetString = "\(target.arch)-\(target.vendor)-\(target.os)"
        guard manifest["target"] as? String == targetString else {
            return .invalid("manifest target does not match \(targetString)")
        }
        guard manifest["stdlibManifestHash"] as? String == BundledStdlib.manifestHash() else {
            return .invalid("manifest stdlibManifestHash does not match bundled sources")
        }

        guard let metadata = manifest["metadata"] as? String,
              let metadataURL = CompilerFileSystem.containedURL(relativePath: metadata, under: rootURL),
              CompilerFileSystem.isRegularFile(at: metadataURL, fileManager: fileManager)
        else {
            return .invalid("metadata file is missing or escapes the artifact")
        }
        guard let inlineKIRDir = manifest["inlineKIRDir"] as? String,
              let inlineURL = CompilerFileSystem.containedURL(relativePath: inlineKIRDir, under: rootURL)
        else {
            return .invalid("inlineKIRDir is missing or escapes the artifact")
        }
        let bundledMemberIndexURL: URL?
        if let bundledMemberIndex = manifest["bundledMemberIndex"] as? String {
            guard let resolved = CompilerFileSystem.containedURL(
                relativePath: bundledMemberIndex,
                under: rootURL
            ),
                CompilerFileSystem.isRegularFile(at: resolved, fileManager: fileManager)
            else {
                return .invalid("bundled member index is missing or escapes the artifact")
            }
            bundledMemberIndexURL = resolved
        } else {
            bundledMemberIndexURL = nil
        }
        if manifest["precomputedSyntheticStubs"] as? Bool == true,
           bundledMemberIndexURL == nil
        {
            return .invalid("precomputed synthetic stubs require a bundled member index")
        }
        var inlineIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inlineURL.path, isDirectory: &inlineIsDirectory), inlineIsDirectory.boolValue else {
            return .invalid("inline-KIR directory is missing")
        }

        guard let objects = manifest["objects"] as? [String], !objects.isEmpty else {
            return .invalid("manifest objects are missing")
        }
        for objectPath in objects {
            guard let objectURL = CompilerFileSystem.containedURL(relativePath: objectPath, under: rootURL),
                  CompilerFileSystem.isRegularFile(at: objectURL, fileManager: fileManager)
            else {
                return .invalid("an object path is missing or escapes the artifact")
            }
        }

        if let prelinkedObject = manifest["prelinkedObject"] as? String {
            guard let prelinkedURL = CompilerFileSystem.containedURL(
                relativePath: prelinkedObject,
                under: rootURL
            ), CompilerFileSystem.isRegularFile(at: prelinkedURL, fileManager: fileManager),
               manifest["prelinkedObjectIncludesRuntime"] as? Bool == true,
               manifest["prelinkedCompilerVersion"] as? String == compilerVersion,
               manifest["prelinkedFormatVersion"] as? Int == 1,
               let runtimeFingerprint = manifest["prelinkedRuntimeFingerprint"] as? String,
               !runtimeFingerprint.isEmpty,
               let linkPlanKey = manifest["prelinkedLinkPlanKey"] as? String,
               !linkPlanKey.isEmpty
            else {
                return .invalid("prelinked runtime object is missing, escapes the artifact, or has an incompatible fingerprint")
            }
        }

        // The manifest lists only object files; inline-KIR blobs are
        // referenced indirectly through the metadata index (`inline=1`
        // records). A cache entry left by an interrupted or racing build can
        // keep the manifest while losing blobs, after which consumers fail
        // lazily with KSWIFTK-LIB-0019 or undefined link symbols. Verify every
        // referenced blob instead of trusting the directory layout.
        guard let metadataData = try? Data(contentsOf: metadataURL) else {
            return .invalid("metadata file is unreadable")
        }
        let inlineNames: Set<String>
        if formatVersion == 2 {
            guard let names = MetadataEncoder.compactInlineKIRMangledNames(in: metadataData) else {
                return .invalid("compact metadata index is malformed")
            }
            inlineNames = Set(names)
        } else {
            guard let metadataText = String(data: metadataData, encoding: .utf8) else {
                return .invalid("metadata file is unreadable")
            }
            inlineNames = inlineKIRMangledNames(metadataText: metadataText)
        }
        for mangledName in inlineNames {
            let blobRelativePath = inlineKIRDir + "/" + MetadataEncoder.inlineKIRFileName(for: mangledName)
            guard let blobURL = CompilerFileSystem.containedURL(relativePath: blobRelativePath, under: rootURL),
                  CompilerFileSystem.isRegularFile(at: blobURL, fileManager: fileManager)
            else {
                return .invalid(
                    "inline KIR blob for '\(mangledName)' is missing or is not a regular file"
                )
            }
        }

        return .valid
    }

    /// Mangled names of every metadata record marked `inline=1` — i.e. every
    /// inline-KIR blob a consumer may demand. Works on both the indexed (v2)
    /// metadata layout, where each index line is prefixed by
    /// "<offset>\t<length>\t", and the legacy line-per-record layout.
    private static func inlineKIRMangledNames(metadataText: String) -> Set<String> {
        var names: Set<String> = []
        for rawLine in metadataText.split(separator: "\n") {
            let record = rawLine.split(separator: "\t").last ?? rawLine
            let fields = record.split(separator: " ")
            guard fields.count >= 2, fields.contains("inline=1") else { continue }
            names.insert(String(fields[1]))
        }
        return names
    }

    private static func currentCompilerFingerprint() -> String? {
        let fileManager = FileManager.default
        guard let executableURL = resolvedExecutableURL() else { return nil }
        let path = executableURL.resolvingSymlinksInPath().path
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.uint64Value,
              let modified = attributes[.modificationDate] as? Date
        else {
            return nil
        }
        return "\(size)-\(modified.timeIntervalSince1970)"
    }

    private static func resolvedExecutableURL() -> URL? {
        let fileManager = FileManager.default
        if let bundleExecutable = Bundle.main.executableURL,
           fileManager.isExecutableFile(atPath: bundleExecutable.path)
        {
            return bundleExecutable
        }
        guard let rawPath = CommandLine.arguments.first, !rawPath.isEmpty else { return nil }
        let rawURL = URL(fileURLWithPath: rawPath)

        if rawURL.path.hasPrefix("/") {
            return rawURL
        }
        if rawPath.contains("/") {
            return URL(fileURLWithPath: fileManager.currentDirectoryPath)
                .appendingPathComponent(rawPath)
        }

        let pathEntries = ProcessInfo.processInfo.environment["PATH"]?
            .split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init) ?? []
        for entry in pathEntries {
            let candidate = URL(fileURLWithPath: entry, isDirectory: true)
                .appendingPathComponent(rawPath)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return Bundle.main.executableURL
    }

    private static func withFileLock<Result>(at path: String, _ body: () throws -> Result) throws -> Result {
        let descriptor = path.withCString { pointer in
            open(pointer, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw Error.lockFileCreateFailed(path: path, errno: errno)
        }
        defer {
            _ = flock(descriptor, LOCK_UN)
            close(descriptor)
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            throw Error.lockFailed(path: path, errno: errno)
        }
        return try body()
    }
}

/// Shared stdlib-only compiler pipeline used by the CLI cache and test cache.
public enum StdlibArtifactBuilder {
    public enum Error: Swift.Error, CustomStringConvertible {
        case diagnostics(String)
        case artifactMissing(String)

        public var description: String {
            switch self {
            case let .diagnostics(message):
                return message
            case let .artifactMissing(path):
                return "artifact was not produced at \(path)"
            }
        }
    }

    public static func build(
        outputBase: String,
        target: TargetTriple,
        includeRuntimePrelink: Bool = false
    ) throws -> String {
        let options = CompilerOptions(
            moduleName: "KSwiftKStdlib",
            inputs: [],
            outputPath: outputBase,
            emit: .library,
            target: target,
            runtimeFlags: ["reflection-metadata=all"],
            includeStdlib: true,
            stdlibOnly: true,
            allowDefaultStdlibLibrary: false
        )
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )

        do {
            try LoadSourcesPhase().run(context)
            try LexPhase().run(context)
            try ParsePhase().run(context)
            try BuildASTPhase().run(context)
            try SemaPhase().run(context)
            try BuildKIRPhase().run(context)
            try LoweringPhase().run(context)
            try CodegenPhase().run(context)
        } catch {
            let diagnostics = context.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: "; ")
            throw Error.diagnostics(diagnostics.isEmpty ? String(describing: error) : diagnostics)
        }

        if context.diagnostics.hasError {
            let diagnostics = context.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: "; ")
            throw Error.diagnostics(diagnostics)
        }

        let artifactPath = outputBase.hasSuffix(".kklib") ? outputBase : outputBase + ".kklib"
        guard FileManager.default.fileExists(atPath: artifactPath) else {
            throw Error.artifactMissing(artifactPath)
        }
        if includeRuntimePrelink {
            attachRuntimePrelinkIfAvailable(outputBase: artifactPath, target: target)
        }
        return artifactPath
    }

    public static func attachRuntimePrelinkIfAvailable(outputBase: String, target: TargetTriple) {
        let artifactPath = outputBase.hasSuffix(".kklib") ? outputBase : outputBase + ".kklib"
        try? attachRuntimePrelinkedObject(to: artifactPath, target: target)
    }

    private static func attachRuntimePrelinkedObject(to artifactPath: String, target: TargetTriple) throws {
        guard target.vendor == "apple", target.os == "macosx" else { return }
        let fileManager = FileManager.default
        let manifestURL = URL(fileURLWithPath: artifactPath).appendingPathComponent("manifest.json")
        guard let manifestData = try? Data(contentsOf: manifestURL),
              var manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let objectPaths = manifest["objects"] as? [String], !objectPaths.isEmpty
        else { return }

        let artifactRoot = URL(fileURLWithPath: artifactPath)
        let stdlibObjects = objectPaths.map { artifactRoot.appendingPathComponent($0).path }
        guard stdlibObjects.allSatisfy({ fileManager.fileExists(atPath: $0) }) else { return }

        let runtime = try CodegenRuntimeSupport.runtimeLinkInputs(target: target, configuration: .release)
        let linker = LinkPhase()
        let swiftcPath = CommandRunner.resolveExecutable("swiftc", fallback: "/usr/bin/swiftc")
        guard let plan = try MacOSLinkerPlan.load(
            swiftcPath: swiftcPath,
            driverArguments: linker.linkerDriverArgs(for: target),
            cacheDirectory: runtime.linkerCacheDirectory
        ) else { return }
        guard let prelinked = MacOSPrelinkedObjects.resolve(
            inputs: runtime.objects + stdlibObjects,
            cacheDirectory: runtime.linkerCacheDirectory.appendingPathComponent("stdlib-prelinked", isDirectory: true),
            driver: plan.executable,
            target: linker.linkerTargetTriple(target)
        ) else { return }

        let relativePath = "objects/KSwiftKStdlibRuntime_prelinked.o"
        let destination = artifactRoot.appendingPathComponent(relativePath)
        try fileManager.copyItem(atPath: prelinked, toPath: destination.path)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
        manifest["prelinkedObject"] = relativePath
        manifest["prelinkedObjectIncludesRuntime"] = true
        manifest["prelinkedCompilerVersion"] = CompilerBuildInfo.version
        manifest["prelinkedFormatVersion"] = 1
        manifest["prelinkedRuntimeFingerprint"] = runtime.fingerprint
        manifest["prelinkedLinkPlanKey"] = plan.cacheKey
        let updatedManifest = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys, .prettyPrinted])
        try updatedManifest.write(to: manifestURL, options: .atomic)
    }
}
