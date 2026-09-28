import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

        // Refuse a cache whose on-disk tree contains an intermediate symlink
        // hop (KUU-806), even when the leaf itself looks regular to lstat.
        guard CacheSecurity.openSafeDirectory(at: cachePath, allowCreate: false) != nil else {
            return
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

        guard let rootFD = CacheSecurity.openSafeDirectory(at: cachePath, allowCreate: false) else {
            return false
        }
        defer { close(rootFD) }

        guard let sourcePath = CacheSecurity.validateContainedArtifactPath(
            cacheRootFD: rootFD,
            cachePath: cachePath,
            relativePath: artifact.relativePath,
            expectedKind: artifact.kind
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

        let destinationPath = Self.outputArtifactPath(for: options)
        let normalizedSource = URL(fileURLWithPath: sourcePath).standardizedFileURL.path
        let normalizedDest = URL(fileURLWithPath: destinationPath).standardizedFileURL.path
        if normalizedSource == normalizedDest {
            return true
        }

        let fm = FileManager.default
        let destinationURL = URL(fileURLWithPath: destinationPath)
        let parent = destinationURL.deletingLastPathComponent().path
        let tempDestinationPath = destinationPath + ".tmp.\(UUID().uuidString)"

        do {
            try fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
            try? fm.removeItem(atPath: tempDestinationPath)
            try fm.copyItem(atPath: sourcePath, toPath: tempDestinationPath)
            if fm.fileExists(atPath: destinationPath) {
                try fm.removeItem(atPath: destinationPath)
            }
            try fm.moveItem(atPath: tempDestinationPath, toPath: destinationPath)
            return true
        } catch {
            try? fm.removeItem(atPath: tempDestinationPath)
            let message = "[IncrementalCompilationCache] Failed to restore cached output at '\(cachePath)': \(error)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            return false
        }
    }

    /// Validates and resolves a manifest-derived `relativePath` against the
    /// cache directory. Returns `nil` if the path is invalid, traverses symlinks,
    /// or resolves outside the cache.
    private static func resolvedAndContainedCachePath(
        relativePath: String,
        cachePath: String,
        expectedKind: CachedOutputArtifactKind = .file
    ) -> String? {
        guard let rootFD = CacheSecurity.openSafeDirectory(at: cachePath, allowCreate: false) else {
            return nil
        }
        defer { close(rootFD) }
        return CacheSecurity.validateContainedArtifactPath(
            cacheRootFD: rootFD,
            cachePath: cachePath,
            relativePath: relativePath,
            expectedKind: expectedKind
        )
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
        guard CacheSecurity.openSafeDirectory(at: cachePath, allowCreate: false) != nil,
              let digests = trustedFileDigests,
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
        guard let rootFD = CacheSecurity.openSafeDirectory(at: cachePath, allowCreate: true) else {
            Self.writeStderr(
                "[IncrementalCompilationCache] Insecure or inaccessible cache directory at '\(cachePath)'\n"
            )
            return
        }
        defer { close(rootFD) }

        do {
            let fingerprints = currentFingerprints.values.sorted(by: { $0.path < $1.path })
            let cachedArtifact = options.flatMap {
                cacheOutputArtifact(for: $0, rootFD: rootFD, fileManager: fm)
            }
            let manifest = CacheManifest(
                version: 1,
                fingerprints: Array(fingerprints),
                buildConfigurationHash: options.map(Self.buildConfigurationHash(for:)),
                outputArtifact: cachedArtifact
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
            let manifestData = try encoder.encode(manifest)
            guard CacheSecurity.writeAtomicFile(in: rootFD, filename: "manifest.json", data: manifestData) else {
                return
            }

            let depsData = try dependencyGraph.serialize()
            guard CacheSecurity.writeAtomicFile(in: rootFD, filename: "deps.json", data: depsData) else {
                return
            }

            if let frontendState {
                let frontendEncoder = JSONEncoder()
                frontendEncoder.outputFormatting = [.sortedKeys, .prettyPrinted]
                let frontendData = try frontendEncoder.encode(frontendState)
                guard CacheSecurity.writeAtomicFile(in: rootFD, filename: "frontend.json", data: frontendData) else {
                    return
                }
            } else {
                CacheSecurity.removeEntryIfPresent(in: rootFD, name: "frontend.json")
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
        rootFD: Int32,
        fileManager fm: FileManager
    ) -> CachedOutputArtifact? {
        let sourcePath = Self.outputArtifactPath(for: options)
        var isDirectory = ObjCBool(false)
        guard fm.fileExists(atPath: sourcePath, isDirectory: &isDirectory) else {
            return nil
        }

        let buildHash = Self.buildConfigurationHash(for: options)
        guard let artifactsFD = CacheSecurity.openSubdirectory(in: rootFD, name: "artifacts", allowCreate: true) else {
            return nil
        }
        defer { close(artifactsFD) }

        guard let hashFD = CacheSecurity.openSubdirectory(in: artifactsFD, name: buildHash, allowCreate: true) else {
            return nil
        }
        defer { close(hashFD) }

        CacheSecurity.removeEntryIfPresent(in: hashFD, name: "output")

        let relativePath = "artifacts/\(buildHash)/output"
        let hashDirPath = cachePath + "/artifacts/" + buildHash
        let tempDestinationPath = hashDirPath + "/output.tmp.\(UUID().uuidString)"

        do {
            try fm.copyItem(atPath: sourcePath, toPath: tempDestinationPath)
            let tmpName = URL(fileURLWithPath: tempDestinationPath).lastPathComponent
            if renameat(hashFD, tmpName, hashFD, "output") != 0 {
                try? fm.removeItem(atPath: tempDestinationPath)
                return nil
            }
            return CachedOutputArtifact(
                kind: isDirectory.boolValue ? .directory : .file,
                relativePath: relativePath
            )
        } catch {
            try? fm.removeItem(atPath: tempDestinationPath)
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

// MARK: - Cache security helper

enum CacheSecurity {
    /// Checks whether the file attributes correspond to ownership by the current effective user
    /// and that neither group-write nor other-write permissions are set.
    static func isOwnerAndModeSecure(st: stat) -> Bool {
        guard st.st_uid == geteuid() else { return false }
        guard (st.st_mode & (mode_t(S_IWGRP) | mode_t(S_IWOTH))) == 0 else { return false }
        return true
    }

    /// Securely verifies and opens the cache root directory descriptor.
    /// Rejects symlinks, unowned directories, and group/other-writable directories.
    static func openSafeDirectory(at path: String, allowCreate: Bool) -> Int32? {
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            guard allowCreate else { return nil }
            do {
                try fm.createDirectory(atPath: path, withIntermediateDirectories: true)
                chmod(path, 0o700)
            } catch {
                return nil
            }
        }

        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else { return nil }
        guard (st.st_mode & mode_t(S_IFMT)) != mode_t(S_IFLNK) else { return nil }
        guard isOwnerAndModeSecure(st: st) else { return nil }

        let fd = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard fd >= 0 else { return nil }

        var fst = stat()
        guard fstat(fd, &fst) == 0 else {
            close(fd)
            return nil
        }
        guard (fst.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            close(fd)
            return nil
        }
        guard isOwnerAndModeSecure(st: fst) else {
            close(fd)
            return nil
        }
        guard fst.st_dev == st.st_dev, fst.st_ino == st.st_ino else {
            close(fd)
            return nil
        }

        return fd
    }

    /// Opens a subdirectory inside parentFD with O_NOFOLLOW.
    /// Rejects symlinks, unowned directories, and group/other-writable directories.
    static func openSubdirectory(in parentFD: Int32, name: String, allowCreate: Bool) -> Int32? {
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            return nil
        }

        if allowCreate {
            if mkdirat(parentFD, name, 0o700) != 0 && errno != EEXIST {
                return nil
            }
        }

        let fd = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }

        var st = stat()
        guard fstat(fd, &st) == 0 else {
            close(fd)
            return nil
        }
        guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            close(fd)
            return nil
        }
        guard isOwnerAndModeSecure(st: st) else {
            close(fd)
            return nil
        }

        return fd
    }

    /// Reads data from a regular file inside parentFD using O_NOFOLLOW.
    static func readData(in parentFD: Int32, filename: String) -> Data? {
        guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("/") else {
            return nil
        }
        let fd = openat(parentFD, filename, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        defer { close(fd) }

        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return nil }
        guard isOwnerAndModeSecure(st: st) else { return nil }

        var data = Data()
        let bufferSize = 8192
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while true {
            let bytesRead = read(fd, &buffer, bufferSize)
            if bytesRead < 0 {
                return nil
            }
            if bytesRead == 0 {
                break
            }
            data.append(buffer, count: bytesRead)
        }
        return data
    }

    /// Writes data atomically into parentFD using a temporary file and renameat.
    static func writeAtomicFile(in parentFD: Int32, filename: String, data: Data) -> Bool {
        guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("/") else {
            return false
        }
        let tmpName = "\(filename).tmp.\(UUID().uuidString)"
        let fd = openat(parentFD, tmpName, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { return false }

        var writtenAll = true
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var remaining = rawBuffer.count
            var offset = 0
            while remaining > 0 {
                let count = write(fd, baseAddress.advanced(by: offset), remaining)
                if count <= 0 {
                    writtenAll = false
                    break
                }
                remaining -= count
                offset += count
            }
        }
        close(fd)

        guard writtenAll else {
            unlinkat(parentFD, tmpName, 0)
            return false
        }

        if renameat(parentFD, tmpName, parentFD, filename) != 0 {
            unlinkat(parentFD, tmpName, 0)
            return false
        }
        return true
    }

    /// Verifies that a directory and all its contents recursively contain no symlinks,
    /// and are owned by the current process euid with no group/other-writable permissions.
    static func verifyNoSymlinksRecursively(dirFD: Int32) -> Bool {
        let dupFD = dup(dirFD)
        guard dupFD >= 0 else { return false }
        guard let dir = fdopendir(dupFD) else {
            close(dupFD)
            return false
        }
        defer { closedir(dir) }

        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 1) { cStr in
                    String(cString: cStr)
                }
            }
            if name == "." || name == ".." {
                continue
            }

            var st = stat()
            guard fstatat(dirFD, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
                return false
            }
            if (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFLNK) {
                return false
            }
            guard isOwnerAndModeSecure(st: st) else {
                return false
            }
            if (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
                let subFD = openat(dirFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard subFD >= 0 else { return false }
                defer { close(subFD) }
                if !verifyNoSymlinksRecursively(dirFD: subFD) {
                    return false
                }
            }
        }
        return true
    }

    /// Removes an entry (file, symlink, or directory) safely without following symlinks.
    static func removeEntryIfPresent(in parentFD: Int32, name: String) {
        var st = stat()
        guard fstatat(parentFD, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
            return
        }
        if (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
            let dirFD = openat(parentFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            if dirFD >= 0 {
                removeDirectoryContentsRecursively(dirFD: dirFD)
                close(dirFD)
            }
            unlinkat(parentFD, name, AT_REMOVEDIR)
        } else {
            unlinkat(parentFD, name, 0)
        }
    }

    private static func removeDirectoryContentsRecursively(dirFD: Int32) {
        let dupFD = dup(dirFD)
        guard dupFD >= 0 else { return }
        guard let dir = fdopendir(dupFD) else {
            close(dupFD)
            return
        }
        defer { closedir(dir) }

        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) { ptr in
                ptr.withMemoryRebound(to: CChar.self, capacity: 1) { cStr in
                    String(cString: cStr)
                }
            }
            if name == "." || name == ".." {
                continue
            }

            var st = stat()
            guard fstatat(dirFD, name, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
                continue
            }
            if (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) {
                let subFD = openat(dirFD, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                if subFD >= 0 {
                    removeDirectoryContentsRecursively(dirFD: subFD)
                    close(subFD)
                }
                unlinkat(dirFD, name, AT_REMOVEDIR)
            } else {
                unlinkat(dirFD, name, 0)
            }
        }
    }

    /// Validates that `relativePath` is fully contained within `cacheRootFD`, traverses intermediate
    /// directories with `O_NOFOLLOW`, rejects any intermediate or final symlinks, verifies owner/mode,
    /// and ensures the actual filesystem kind matches `expectedKind`.
    /// Returns the verified canonical source path if valid, or `nil` if rejected.
    static func validateContainedArtifactPath(
        cacheRootFD: Int32,
        cachePath: String,
        relativePath: String,
        expectedKind: CachedOutputArtifactKind
    ) -> String? {
        guard !relativePath.isEmpty, !relativePath.hasPrefix("/") else {
            return nil
        }
        let components = relativePath.components(separatedBy: "/")
        guard !components.isEmpty else { return nil }
        for comp in components {
            guard !comp.isEmpty, comp != ".", comp != ".." else { return nil }
        }

        var currentFD = cacheRootFD
        var fdsToClose: [Int32] = []
        defer {
            for fd in fdsToClose {
                close(fd)
            }
        }

        // Traverse intermediate directories with O_NOFOLLOW
        if components.count > 1 {
            for comp in components.dropLast() {
                let nextFD = openat(currentFD, comp, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard nextFD >= 0 else { return nil }
                fdsToClose.append(nextFD)

                var st = stat()
                guard fstat(nextFD, &st) == 0 else { return nil }
                guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else { return nil }
                guard isOwnerAndModeSecure(st: st) else { return nil }

                currentFD = nextFD
            }
        }

        let lastComp = components.last!
        var st = stat()
        guard fstatat(currentFD, lastComp, &st, AT_SYMLINK_NOFOLLOW) == 0 else {
            return nil
        }
        // Reject any symlink
        guard (st.st_mode & mode_t(S_IFMT)) != mode_t(S_IFLNK) else {
            return nil
        }
        guard isOwnerAndModeSecure(st: st) else {
            return nil
        }

        switch expectedKind {
        case .file:
            guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG) else { return nil }
        case .directory:
            guard (st.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else { return nil }
            let dirFD = openat(currentFD, lastComp, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard dirFD >= 0 else { return nil }
            defer { close(dirFD) }
            guard verifyNoSymlinksRecursively(dirFD: dirFD) else { return nil }
        }

        return cachePath + "/" + relativePath
    }
}
