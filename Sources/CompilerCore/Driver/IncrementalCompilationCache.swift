import Foundation

/// Manages the on-disk cache for incremental compilation.
///
/// The primary cache files used by this type are:
/// ```
/// <cachePath>/
///   manifest.json       — file fingerprints from the previous build
///   deps.json           — dependency graph (symbol ↔ file relationships)
///   frontend.json       — reusable AST/interner state for file-level frontend work
///   integrity.json      — keyed MAC index authenticating every file above
///   artifacts/          — final output artifacts keyed by build configuration
/// ```
///
/// The cache is a trust boundary: it is only read after its location and
/// contents pass `IncrementalCacheTrust` validation, so a cache shipped
/// inside a workspace or tampered with on disk falls back to a full build
/// instead of restoring arbitrary outputs.
public final class IncrementalCompilationCache {
    public let cachePath: String

    /// Root of the managed cache ancestry inside which every directory up to
    /// `cachePath` must be private. Non-nil only for the compiler-managed
    /// default location; explicit `--incremental-cache` paths are leaf-checked
    /// and authenticated by the integrity index instead.
    private let managedAncestorBase: String?

    private var previousFingerprints: [String: FileFingerprint] = [:]
    private var previousBuildConfigurationHash: String?
    private var previousOutputArtifact: CachedOutputArtifact?

    /// Authenticated digests of the cache files, loaded from `integrity.json`.
    /// Nil until `loadPreviousState` (or `saveState`) authenticates the cache.
    private var trustedFileDigests: [String: String]?

    /// Dependency graph from the *previous* successful compilation.
    /// `nil` means no valid dependency graph was loaded (deps.json missing or corrupt).
    private var previousDependencyGraph: DependencyGraph?

    /// Fingerprints computed for the *current* compilation inputs.
    private var currentFingerprints: [String: FileFingerprint] = [:]

    /// Test hook: when set, the compiler-managed default cache root moves to
    /// this directory instead of the per-user caches directory.
    nonisolated(unsafe) public static var userCacheRootOverride: String?

    public init(cachePath: String, managedAncestorBase: String? = nil) {
        self.cachePath = IncrementalCacheTrust.normalize(cachePath)
        self.managedAncestorBase = managedAncestorBase.map(IncrementalCacheTrust.normalize)
    }

    // MARK: - Compiler-managed default location

    /// Per-user private cache root for compiler-managed state: the
    /// `<caches>/kswiftk` directory holding the integrity key and the
    /// namespaced incremental caches.
    public static func userPrivateCacheBase(allowOverride: Bool = true) -> String? {
        if allowOverride, let override = userCacheRootOverride {
            return IncrementalCacheTrust.normalize(override)
        }
        guard let caches = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first
        else {
            return nil
        }
        return caches.path + "/kswiftk"
    }

    /// Directory isolating this workspace and build: namespaced by repository
    /// identity, compiler build, and the resolved input set so caches from
    /// other projects or toolchains never collide.
    public static func defaultCachePath(for options: CompilerOptions) -> String? {
        userPrivateCacheBase().map { $0 + "/incremental/" + namespace(for: options) }
    }

    /// Cache for the compiler-managed default location, or nil when no
    /// per-user caches directory is available (incremental then compiles
    /// uncached rather than falling back to a workspace directory).
    public static func makeDefault(for options: CompilerOptions) -> IncrementalCompilationCache? {
        guard let base = userPrivateCacheBase() else {
            return nil
        }
        return IncrementalCompilationCache(
            cachePath: base + "/incremental/" + namespace(for: options),
            managedAncestorBase: base
        )
    }

    /// Stable identifier for the cache namespace: repository root (or output
    /// parent outside a worktree), compiler build, and resolved input paths.
    public static func namespace(for options: CompilerOptions) -> String {
        let fm = FileManager.default
        let outputParent = URL(fileURLWithPath: options.outputPath)
            .deletingLastPathComponent()
        let resolvedOutputParent = outputParent.standardized
            .resolvingSymlinksInPath().path
        // The worktree root (the directory containing `.git`, which can also
        // be a file for linked worktrees) is the repository identity; outside
        // a worktree the output directory itself stands in.
        var repositoryIdentity = resolvedOutputParent
        var cursor = resolvedOutputParent
        while true {
            if fm.fileExists(atPath: cursor + "/.git") {
                repositoryIdentity = cursor
                break
            }
            let parent = URL(fileURLWithPath: cursor).deletingLastPathComponent().path
            if parent == cursor {
                break
            }
            cursor = parent
        }
        let resolvedInputs = options.inputs.map {
            URL(fileURLWithPath: $0).standardized.resolvingSymlinksInPath().path
        }.sorted()
        let material = (["kswiftk-incremental-namespace/v1", repositoryIdentity, CompilerBuildInfo.version] + resolvedInputs)
            .joined(separator: "\n")
        return FileFingerprint.sha256Hex(Data(material.utf8))
    }

    // MARK: - Loading previous state

    private static let supportedManifestVersion = 1

    /// Loads the manifest and dependency graph from the cache directory.
    /// The location must pass trust validation and every file read must match
    /// the authenticated integrity index; a cache that fails either check —
    /// including one committed inside a workspace — is ignored so the build
    /// starts fresh.
    public func loadPreviousState() {
        let fm = FileManager.default
        switch IncrementalCacheTrust.validateLocation(
            cachePath: cachePath,
            managedAncestorBase: managedAncestorBase
        ) {
        case .missing:
            return
        case let .untrusted(reason):
            Self.writeStderr(
                "[IncrementalCompilationCache] Ignoring untrusted cache at '\(cachePath)': \(reason)\n"
            )
            return
        case .trusted:
            break
        }

        guard let digests = IncrementalCacheTrust.readIntegrityIndex(cachePath: cachePath) else {
            if fm.fileExists(atPath: cachePath + "/manifest.json") {
                Self.writeStderr(
                    "[IncrementalCompilationCache] Ignoring unauthenticated cache at '\(cachePath)'\n"
                )
            }
            return
        }
        trustedFileDigests = digests

        if let data = IncrementalCacheTrust.authenticatedFileData(
            cachePath: cachePath,
            relativePath: "manifest.json",
            index: digests
        ), let manifest = try? JSONDecoder().decode(CacheManifest.self, from: data),
           manifest.version == Self.supportedManifestVersion
        {
            for fp in manifest.fingerprints {
                previousFingerprints[fp.path] = fp
            }
            previousBuildConfigurationHash = manifest.buildConfigurationHash
            previousOutputArtifact = manifest.outputArtifact
        }

        if let data = IncrementalCacheTrust.authenticatedFileData(
            cachePath: cachePath,
            relativePath: "deps.json",
            index: digests
        ), let graph = try? DependencyGraph.deserialize(from: data) {
            previousDependencyGraph = graph
        }
    }

    // MARK: - Change detection

    public func computeCurrentFingerprints(for paths: [String], sourceManager: SourceManager) {
        currentFingerprints = [:]
        for path in paths {
            guard let fingerprint = computeCurrentFingerprint(for: path, sourceManager: sourceManager) else {
                continue
            }
            currentFingerprints[path] = fingerprint
        }
    }

    public func computeCurrentFingerprints(for paths: [String]) {
        currentFingerprints = [:]
        for path in paths {
            guard let fingerprint = computeCurrentFingerprint(for: path, sourceManager: nil) else {
                continue
            }
            currentFingerprints[path] = fingerprint
        }
    }

    public func changedFiles(allPaths: [String]) -> Set<String> {
        var changed = Set<String>()
        let allPathsSet = Set(allPaths)
        for path in allPaths {
            guard let current = currentFingerprints[path] else {
                // File could not be fingerprinted — treat as changed.
                changed.insert(path)
                continue
            }
            guard let previous = previousFingerprints[path] else {
                // New file — treat as changed.
                changed.insert(path)
                continue
            }
            if current.contentChanged(from: previous) {
                changed.insert(path)
            }
        }
        // Files that were in the previous build but removed in this build
        // must be treated as changed so their provided symbols are invalidated
        // and dependents are recompiled.
        for previousPath in previousFingerprints.keys where !allPathsSet.contains(previousPath) {
            changed.insert(previousPath)
        }
        return changed
    }

    /// Computes the full recompilation set using the dependency graph.
    /// Returns `nil` if no cache is available (full build needed), including
    /// when the dependency graph is missing or corrupt.
    public func recompilationSet(allPaths: [String], options: CompilerOptions? = nil) -> Set<String>? {
        if previousFingerprints.isEmpty {
            // No previous build — full build needed.
            return nil
        }

        if let options,
           previousBuildConfigurationHash != Self.buildConfigurationHash(for: options)
        {
            return nil
        }

        guard let depGraph = previousDependencyGraph else {
            // Dependency graph missing or corrupt — full build needed.
            return nil
        }

        let changed = changedFiles(allPaths: allPaths)
        if changed.isEmpty {
            return Set()
        }

        let recompFiles = depGraph.recompilationSet(
            changedFiles: changed,
            allFiles: allPaths
        )
        return Set(recompFiles)
    }

    public func restoreCachedOutput(for options: CompilerOptions) -> Bool {
        guard previousBuildConfigurationHash == Self.buildConfigurationHash(for: options),
              let artifact = previousOutputArtifact
        else {
            return false
        }

        guard let sourcePath = Self.resolvedAndContainedCachePath(
            relativePath: artifact.relativePath,
            cachePath: cachePath
        ) else {
            return false
        }

        // Re-verify the artifact bytes against the authenticated index at
        // restore time so content swapped in after the state load is caught.
        guard let digests = trustedFileDigests,
              IncrementalCacheTrust.verifyArtifact(
                  cachePath: cachePath,
                  artifact: artifact,
                  index: digests
              )
        else {
            return false
        }

        var sourceIsDirectory = ObjCBool(false)
        let fm = FileManager.default
        guard fm.fileExists(atPath: sourcePath, isDirectory: &sourceIsDirectory) else {
            return false
        }
        if artifact.kind == .directory, !sourceIsDirectory.boolValue {
            return false
        }
        if artifact.kind == .file, sourceIsDirectory.boolValue {
            return false
        }

        let destinationPath = Self.outputArtifactPath(for: options)
        if URL(fileURLWithPath: sourcePath).standardizedFileURL.path
            == URL(fileURLWithPath: destinationPath).standardizedFileURL.path
        {
            return true
        }

        do {
            try Self.removeItemIfPresent(at: destinationPath, fileManager: fm)
            let parent = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try fm.copyItem(atPath: sourcePath, toPath: destinationPath)
            return true
        } catch {
            let message = "[IncrementalCompilationCache] Failed to restore cached output at '\(cachePath)': \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            return false
        }
    }

    /// Validates and resolves a manifest-derived `relativePath` against the
    /// cache directory. Returns `nil` if the path is absolute, contains `..`
    /// components, or resolves outside the cache.
    private static func resolvedAndContainedCachePath(relativePath: String, cachePath: String) -> String? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            return nil
        }

        let components = relativePath.components(separatedBy: "/")
        guard !components.contains("..") else {
            return nil
        }

        let cacheURL = URL(fileURLWithPath: cachePath).standardized
        let sourceURL = cacheURL.appendingPathComponent(relativePath).standardized
        let sourceResolved = sourceURL.path
        let cacheResolved = cacheURL.path

        let cachePrefix = cacheResolved.hasSuffix("/") ? cacheResolved : cacheResolved + "/"
        guard sourceResolved != cacheResolved, sourceResolved.hasPrefix(cachePrefix) else {
            return nil
        }

        return sourceResolved
    }

    public var hasPreviousCache: Bool {
        !previousFingerprints.isEmpty
    }

    public var dependencyGraph: DependencyGraph? {
        previousDependencyGraph
    }

    public func buildConfigurationHash(for options: CompilerOptions) -> String {
        Self.buildConfigurationHash(for: options)
    }

    public func loadFrontendState(for options: CompilerOptions) -> IncrementalFrontendState? {
        let buildHash = Self.buildConfigurationHash(for: options)
        guard previousBuildConfigurationHash == buildHash else {
            return nil
        }
        guard let digests = trustedFileDigests,
              let data = IncrementalCacheTrust.authenticatedFileData(
                  cachePath: cachePath,
                  relativePath: "frontend.json",
                  index: digests
              )
        else {
            return nil
        }
        guard let state = try? JSONDecoder().decode(IncrementalFrontendState.self, from: data),
              state.version == IncrementalFrontendState.supportedVersion,
              state.buildConfigurationHash == buildHash
        else {
            return nil
        }
        return state
    }

    // MARK: - Saving state

    /// Saves the current fingerprints and the updated dependency graph to disk.
    public func saveState(
        dependencyGraph: DependencyGraph,
        options: CompilerOptions? = nil,
        frontendState: IncrementalFrontendState? = nil
    ) {
        let fm = FileManager.default

        // The cache may only ever live in a private, current-user-owned
        // directory — refuse to write into anything else.
        guard IncrementalCacheTrust.ensureSecureLocation(
            cachePath: cachePath,
            managedAncestorBase: managedAncestorBase
        ) else {
            Self.writeStderr(
                "[IncrementalCompilationCache] Skipping cache save at untrusted location '\(cachePath)'\n"
            )
            return
        }

        do {
            let fingerprints = currentFingerprints.values.sorted(by: { $0.path < $1.path })
            let manifest = CacheManifest(
                version: 1,
                fingerprints: Array(fingerprints),
                buildConfigurationHash: options.map(Self.buildConfigurationHash(for:)),
                outputArtifact: options.flatMap { cacheOutputArtifact(for: $0, fileManager: fm) }
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let manifestData = try encoder.encode(manifest)
            try manifestData.write(
                to: URL(fileURLWithPath: cachePath + "/manifest.json"),
                options: .atomic
            )

            let depsData = try dependencyGraph.serialize()
            try depsData.write(
                to: URL(fileURLWithPath: cachePath + "/deps.json"),
                options: .atomic
            )

            if let frontendState {
                let frontendEncoder = JSONEncoder()
                frontendEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                let frontendData = try frontendEncoder.encode(frontendState)
                try frontendData.write(
                    to: URL(fileURLWithPath: cachePath + "/frontend.json"),
                    options: .atomic
                )
            } else {
                try? fm.removeItem(atPath: cachePath + "/frontend.json")
            }

            // Publish the authenticated index last so the new state is only
            // trusted once every file on disk matches it.
            guard let digests = IncrementalCacheTrust.writeIntegrityIndex(cachePath: cachePath) else {
                Self.writeStderr(
                    "[IncrementalCompilationCache] Failed to authenticate cache at '\(cachePath)'\n"
                )
                return
            }
            trustedFileDigests = digests

            previousFingerprints = currentFingerprints
            previousBuildConfigurationHash = manifest.buildConfigurationHash
            previousOutputArtifact = manifest.outputArtifact
            previousDependencyGraph = dependencyGraph
        } catch {
            // Cache save failure is non-fatal — next build will do a full compile.
            let message = "[IncrementalCompilationCache] Failed to save cache at '\(cachePath)': \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
        }
    }

    private func computeCurrentFingerprint(for path: String, sourceManager: SourceManager?) -> FileFingerprint? {
        if let sourceManager, let fileID = sourceManager.fileID(forPath: path) {
            let contents = sourceManager.contents(of: fileID)
            return FileFingerprint.compute(for: path, contents: contents)
        }
        return FileFingerprint.compute(for: path)
    }

    private func cacheOutputArtifact(
        for options: CompilerOptions,
        fileManager fm: FileManager
    ) -> CachedOutputArtifact? {
        let sourcePath = Self.outputArtifactPath(for: options)
        var isDirectory = ObjCBool(false)
        guard fm.fileExists(atPath: sourcePath, isDirectory: &isDirectory) else {
            return nil
        }

        let relativePath = "artifacts/\(Self.buildConfigurationHash(for: options))/output"
        let destinationPath = cachePath + "/" + relativePath
        do {
            try Self.removeItemIfPresent(at: destinationPath, fileManager: fm)
            let parent = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try fm.copyItem(atPath: sourcePath, toPath: destinationPath)
            return CachedOutputArtifact(
                kind: isDirectory.boolValue ? .directory : .file,
                relativePath: relativePath
            )
        } catch {
            let message = "[IncrementalCompilationCache] Failed to cache output artifact at '\(cachePath)': \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            return nil
        }
    }

    private static func writeStderr(_ message: String) {
        if let data = message.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    private static func removeItemIfPresent(at path: String, fileManager fm: FileManager) throws {
        if fm.fileExists(atPath: path) {
            try fm.removeItem(atPath: path)
        }
    }

    private static func outputArtifactPath(for options: CompilerOptions) -> String {
        switch options.emit {
        case .kirDump:
            outputPath(base: options.outputPath, defaultExtension: "kir")
        case .llvmIR:
            outputPath(base: options.outputPath, defaultExtension: "ll")
        case .object:
            outputPath(base: options.outputPath, defaultExtension: "o")
        case .executable:
            options.outputPath
        case .library:
            options.outputPath.hasSuffix(".kklib") ? options.outputPath : options.outputPath + ".kklib"
        }
    }

    private static func outputPath(base: String, defaultExtension: String) -> String {
        let fileURL = URL(fileURLWithPath: base)
        if fileURL.pathExtension.isEmpty {
            return fileURL.appendingPathExtension(defaultExtension).path
        }
        return base
    }

    private static func buildConfigurationHash(for options: CompilerOptions) -> String {
        let stdlibManifestHash: String
        if let artifactPath = options.stdlibLibraryPath {
            // Hash the manifest advertised by the selected artifact, rather
            // than only the compiler's bundled hash. This prevents a cache hit
            // when a caller replaces the artifact at the same path.
            let manifestPath = URL(fileURLWithPath: artifactPath)
                .appendingPathComponent("manifest.json")
            if let data = try? Data(contentsOf: manifestPath),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let hash = object["stdlibManifestHash"] as? String,
               !hash.isEmpty
            {
                stdlibManifestHash = hash
            } else {
                stdlibManifestHash = "missing"
            }
        } else if options.includeStdlib || options.stdlibOnly {
            stdlibManifestHash = BundledStdlib.manifestHash()
        } else {
            stdlibManifestHash = ""
        }
        let config = IncrementalBuildConfiguration(
            schemaVersion: 1,
            moduleName: options.moduleName,
            inputPaths: options.inputs,
            emit: options.emit.rawValue,
            searchPaths: options.effectiveLibrarySearchPaths,
            libraryPaths: options.libraryPaths,
            linkLibraries: options.linkLibraries,
            target: IncrementalTargetTriple(
                arch: options.target.arch,
                vendor: options.target.vendor,
                os: options.target.os,
                osVersion: options.target.osVersion
            ),
            optLevel: options.optLevel.rawValue,
            debugInfo: options.debugInfo,
            frontendFlags: options.frontendFlags.filter(Self.isOutputAffectingFrontendFlag),
            irFlags: options.irFlags,
            runtimeFlags: options.runtimeFlags,
            stdlibOnly: options.stdlibOnly,
            stdlibLibraryPath: options.stdlibLibraryPath,
            stdlibManifestHash: stdlibManifestHash
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(config)) ?? Data()
        return stableFNV1a64Hex(String(decoding: data, as: UTF8.self))
    }

    private static func isOutputAffectingFrontendFlag(_ flag: String) -> Bool {
        flag != "incremental" && flag != "time-phases" && !flag.hasPrefix("jobs=")
    }

    private static func stableFNV1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}

// MARK: - Cache manifest model

struct CacheManifest: Codable {
    let version: Int
    let fingerprints: [FileFingerprint]
    let buildConfigurationHash: String?
    let outputArtifact: CachedOutputArtifact?

    init(
        version: Int,
        fingerprints: [FileFingerprint],
        buildConfigurationHash: String? = nil,
        outputArtifact: CachedOutputArtifact? = nil
    ) {
        self.version = version
        self.fingerprints = fingerprints
        self.buildConfigurationHash = buildConfigurationHash
        self.outputArtifact = outputArtifact
    }
}

struct CachedOutputArtifact: Codable, Equatable {
    let kind: CachedOutputArtifactKind
    let relativePath: String
}

enum CachedOutputArtifactKind: String, Codable {
    case file
    case directory
}

private struct IncrementalBuildConfiguration: Encodable {
    let schemaVersion: Int
    let moduleName: String
    let inputPaths: [String]
    let emit: String
    let searchPaths: [String]
    let libraryPaths: [String]
    let linkLibraries: [String]
    let target: IncrementalTargetTriple
    let optLevel: Int
    let debugInfo: Bool
    let frontendFlags: [String]
    let irFlags: [String]
    let runtimeFlags: [String]
    let stdlibOnly: Bool
    let stdlibLibraryPath: String?
    let stdlibManifestHash: String
}

private struct IncrementalTargetTriple: Encodable {
    let arch: String
    let vendor: String
    let os: String
    let osVersion: String?
}
