import Foundation

#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif

import CompilerCore

private final class RuntimeObjectCache: @unchecked Sendable {
    private let condition = NSCondition()
    private var cachedPathsByKey: [String: [String]] = [:]
    private var loadingKeys: Set<String> = []

    func getOrLoad(cacheKey: String, loader: () throws -> [String]) throws -> [String] {
        condition.lock()
        while true {
            if let cachedPaths = cachedPathsIfValid(for: cacheKey) {
                condition.unlock()
                return cachedPaths
            }
            if !loadingKeys.contains(cacheKey) {
                loadingKeys.insert(cacheKey)
                condition.unlock()

                do {
                    let loadedPaths = try loader()
                    condition.lock()
                    cachedPathsByKey[cacheKey] = loadedPaths
                    loadingKeys.remove(cacheKey)
                    condition.broadcast()
                    condition.unlock()
                    return loadedPaths
                } catch {
                    condition.lock()
                    loadingKeys.remove(cacheKey)
                    condition.broadcast()
                    condition.unlock()
                    throw error
                }
            }
            condition.wait()
        }
    }

    private func cachedPathsIfValid(for cacheKey: String) -> [String]? {
        guard let cachedPaths = cachedPathsByKey[cacheKey],
              cachedPaths.allSatisfy({ FileManager.default.fileExists(atPath: $0) })
        else {
            return nil
        }
        return cachedPaths
    }
}

enum CodegenRuntimeSupportError: Error, CustomStringConvertible {
    case runtimeObjectsUnavailable(String)
    case runtimeBuildFailed(String)
    case untrustedRuntimePackageRoot(String)
    case runtimePackageRootUnavailable(String)

    var description: String {
        switch self {
        case let .runtimeObjectsUnavailable(path):
            "Unable to locate packaged runtime object files under \(path)."
        case let .runtimeBuildFailed(reason):
            "Failed to build packaged runtime objects: \(reason)"
        case let .untrustedRuntimePackageRoot(reason):
            "Runtime objects cannot be built from an untrusted package root: \(reason)"
        case let .runtimePackageRootUnavailable(reason):
            "Unable to locate a compiler-owned KSwiftK package root for building runtime objects: \(reason). Set KSWIFTK_PACKAGE_ROOT to a verified KSwiftK checkout to override the search."
        }
    }
}

enum RuntimeBuildConfiguration: String {
    case debug
    case release
}

extension CodegenRuntimeSupport {
    private static let runtimeObjectCache = RuntimeObjectCache()

    static func runtimeObjectPaths(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration = .release
    ) throws -> [String] {
        try runtimeLinkInputs(target: target, configuration: configuration).objects
    }

    /// Resolve and verify the package once, then carry its fingerprint and layout
    /// through discovery/build instead of re-enumerating sources for each path.
    static func runtimeLinkInputs(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration = .release
    ) throws -> (objects: [String], linkerCacheDirectory: URL) {
        let packageRoot = try runtimePackageRootURL()
        let cacheKey = try runtimeBuildCacheKey(target: target, configuration: configuration, packageRoot: packageRoot)
        let scratchRoot = runtimeSharedScratchRoot()
        let buildRoot = scratchRoot.appendingPathComponent(cacheKey, isDirectory: true)
        let buildDirectory = buildRoot
            .appendingPathComponent(runtimeBuildCacheDirectoryComponent(target: target), isDirectory: true)
            .appendingPathComponent(configuration.rawValue, isDirectory: true)
            .appendingPathComponent("Runtime.build", isDirectory: true)
        let objects = try runtimeObjectCache.getOrLoad(cacheKey: cacheKey) {
            try withRuntimeBuildLock(cacheKey: cacheKey, scratchRoot: scratchRoot) {
                // Only a manifest written after a completed, locked build proves
                // that the scratch directory contains the full runtime object set.
                let manifestURL = buildRoot.appendingPathComponent("objects-\(configuration.rawValue).manifest")
                let discovered = manifestValidatedRuntimeObjectPaths(manifestURL: manifestURL)
                if !discovered.isEmpty { return discovered }

                try buildRuntimeObjects(
                    packageRoot: packageRoot,
                    arguments: swiftBuildArguments(target: target, configuration: configuration, scratchDirectory: buildRoot)
                )
                let built = discoverRuntimeObjectPaths(
                    inScratchBuildDirectory: buildDirectory, scratchRootDirectory: buildRoot
                )
                if !built.isEmpty {
                    try writeRuntimeObjectsManifest(built, to: manifestURL)
                    return built
                }

                let fallback = discoverPackageBuildRuntimeObjectPaths(
                    target: target, configuration: configuration, packageRoot: packageRoot
                )
                guard !fallback.isEmpty else {
                    throw CodegenRuntimeSupportError.runtimeObjectsUnavailable(buildDirectory.path)
                }
                return fallback
            }
        }
        // Link plans embed per-checkout toolchain state, so they stay beside
        // the package rather than in the shared object cache.
        return (objects, packageRoot.appendingPathComponent(".runtime-build/link-plans", isDirectory: true))
    }

    private static func buildRuntimeObjects(packageRoot: URL, arguments: [String]) throws {
        let swiftPath = CommandRunner.resolveExecutable("swift", fallback: "/usr/bin/swift")
        do {
            _ = try CommandRunner.run(
                executable: swiftPath,
                arguments: arguments,
                currentDirectoryPath: packageRoot.path,
                phaseTimer: nil,
                subPhaseName: "Link/swift-runtime-build",
                timeout: runtimeBuildTimeoutSeconds()
            )
        } catch let error as CommandRunnerError {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(describeBuild(error))
        } catch {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(String(describing: error))
        }
    }

    // A from-scratch `swift build -c release --target Runtime` (first run in
    // a new worktree, or after `--clean-runtime-cache`) measured 225-330s on
    // a moderately loaded machine, so this default leaves headroom above
    // that observed range. KSWIFTK_RUNTIME_BUILD_TIMEOUT overrides it for
    // machines that are slower or more heavily loaded still.
    private static let defaultRuntimeBuildTimeoutSeconds: TimeInterval = 600

    // Exposed for testing, like discoverRuntimeObjectPaths below.
    static func runtimeBuildTimeoutSeconds(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> TimeInterval {
        guard let raw = environment["KSWIFTK_RUNTIME_BUILD_TIMEOUT"],
              let parsed = TimeInterval(raw),
              parsed.isFinite,
              parsed > 0
        else {
            return defaultRuntimeBuildTimeoutSeconds
        }
        return parsed
    }

    private static func describeBuild(_ error: CommandRunnerError) -> String {
        switch error {
        case let .launchFailed(reason):
            return reason
        case let .nonZeroExit(result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return stderr.isEmpty ? "swift build exited with code \(result.exitCode)." : stderr
        case let .timedOut(reason):
            return "\(reason) Set KSWIFTK_RUNTIME_BUILD_TIMEOUT (seconds) to allow more time."
        }
    }

    // Exposed for testing, like discoverRuntimeObjectPaths below.
    static func writeRuntimeObjectsManifest(_ paths: [String], to manifestURL: URL) throws {
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try (paths.joined(separator: "\n") + "\n")
            .write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    // Returns the manifest's object paths only while every one of them still
    // exists; anything else (no manifest, empty manifest, missing object)
    // reports a cache miss so the runtime build re-runs.
    static func manifestValidatedRuntimeObjectPaths(manifestURL: URL) -> [String] {
        guard let contents = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            return []
        }
        let paths = contents
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard !paths.isEmpty,
              paths.allSatisfy({ FileManager.default.fileExists(atPath: $0) })
        else {
            return []
        }
        return paths
    }

    // Exposed for testing so the discovery/fallback logic can be exercised
    // against synthesized on-disk layouts without running a real build.
    static func discoverRuntimeObjectPaths(
        inScratchBuildDirectory buildDirectory: URL,
        scratchRootDirectory rootDirectory: URL
    ) -> [String] {
        let discovered = discoverRuntimeObjectPaths(in: [buildDirectory, rootDirectory])
        if !discovered.isEmpty {
            return discovered
        }

        // Whole-module-optimization (WMO) toolchains emit a single
        // consolidated object for the Runtime module instead of a
        // "Runtime.build" directory full of per-file `.swift.o` objects.
        // Some toolchains place that single object directly in the build
        // directory rather than inside a "*.build" products directory, so
        // the directory-name based discovery above finds nothing (BUG-051).
        return discoverWholeModuleRuntimeObjectPaths(nearBuildDirectory: buildDirectory)
    }

    private static func discoverPackageBuildRuntimeObjectPaths(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration,
        packageRoot: URL
    ) -> [String] {
        let packageBuildRoot = packageRoot
            .appendingPathComponent(".build", isDirectory: true)
        let targetBuildRoot = packageBuildRoot
            .appendingPathComponent(runtimeBuildCacheDirectoryComponent(target: target), isDirectory: true)
        let searchRoots = [
            targetBuildRoot.appendingPathComponent(configuration.rawValue, isDirectory: true),
            packageBuildRoot.appendingPathComponent(configuration.rawValue, isDirectory: true),
        ]
        return discoverRuntimeObjectPaths(in: searchRoots)
    }

    private static func discoverRuntimeObjectPaths(in searchRoots: [URL]) -> [String] {
        for searchRoot in searchRoots {
            if let candidates = discoverRuntimeObjectPaths(in: searchRoot), !candidates.isEmpty {
                return candidates
            }
        }
        return []
    }

    private static func discoverRuntimeObjectPaths(in searchRoot: URL) -> [String]? {
        var candidates = collectObjectPaths(in: searchRoot)
        if !candidates.isEmpty {
            return candidates + runtimeABIObjectPaths(near: searchRoot)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: searchRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let directoryURL as URL in enumerator {
            guard runtimeBuildProductsDirectoryNames.contains(directoryURL.lastPathComponent) else {
                continue
            }
            candidates = collectObjectPathsRecursively(in: directoryURL)
            if !candidates.isEmpty {
                return candidates + runtimeABIObjectPaths(near: directoryURL)
            }
        }
        return nil
    }

    // "Runtime.build" is the classic SwiftPM/llbuild layout, where object
    // files sit directly inside it. "Runtime-t.build" is the newer Swift
    // Build (XCBuild) engine's per-target layout, which `swift build` uses
    // by default on newer toolchains; there, objects sit one level deeper
    // (Objects-normal/<arch>/*.o), hence the recursive collection below.
    private static let runtimeBuildProductsDirectoryNames: Set<String> = ["Runtime.build", "Runtime-t.build"]

    private static func runtimeABIObjectPaths(near runtimeDirectory: URL) -> [String] {
        let parent = runtimeDirectory.deletingLastPathComponent()
        for name in ["RuntimeABI.build", "RuntimeABI-t.build"] {
            let paths = collectObjectPathsRecursively(in: parent.appendingPathComponent(name, isDirectory: true))
            if !paths.isEmpty { return paths }
        }
        return ["RuntimeABI.o", "RuntimeABI.swift.o"].compactMap { name in
            let path = parent.appendingPathComponent(name).path
            return FileManager.default.fileExists(atPath: path) ? path : nil
        }
    }

    private static func collectObjectPaths(in directory: URL) -> [String] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return entries
            .filter { $0.lastPathComponent.hasSuffix(".o") }
            .map(\.path)
            .sorted()
    }

    // Only called once a directory is already confirmed to be a Runtime
    // build-products directory (see `runtimeBuildProductsDirectoryNames`),
    // so widening the walk to the whole subtree can't pull in objects
    // belonging to unrelated targets.
    private static func collectObjectPathsRecursively(in directory: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            guard fileURL.lastPathComponent.hasSuffix(".o") else { continue }
            paths.append(fileURL.path)
        }
        return paths.sorted()
    }

    // File names a WMO build uses for the Runtime module's single
    // consolidated object. Scoped to exact names so the fallback never
    // grabs per-file `.swift.o` objects, another target's object (e.g.
    // "CompilerCore.o"), or the AST-wrapper debug object SwiftPM emits under
    // "Modules/Runtime.o" (which contains only "__Swift_AST", no code).
    private static let wholeModuleRuntimeObjectNames: Set<String> = ["Runtime.o", "Runtime.swift.o"]

    // The single WMO object, when it isn't nested in a "*.build" products
    // directory, sits directly in the build configuration directory that
    // otherwise contains "Runtime.build". Scan only that directory's direct
    // children so the "Modules/" AST-wrapper object stays excluded.
    private static func discoverWholeModuleRuntimeObjectPaths(nearBuildDirectory buildDirectory: URL) -> [String] {
        let enclosingDirectory = buildDirectory.deletingLastPathComponent()
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: enclosingDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let runtimePaths = entries
            .filter { wholeModuleRuntimeObjectNames.contains($0.lastPathComponent) }
            .map(\.path)
            .sorted()
        guard !runtimePaths.isEmpty else { return [] }
        return runtimePaths + runtimeABIObjectPaths(near: buildDirectory)
    }

    static func runtimeBuildDirectory(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) throws -> URL {
        try runtimeBuildScratchDirectory(target: target, configuration: configuration)
            .appendingPathComponent(runtimeBuildCacheDirectoryComponent(target: target), isDirectory: true)
            .appendingPathComponent(configuration.rawValue, isDirectory: true)
            .appendingPathComponent("Runtime.build", isDirectory: true)
    }

    private static func runtimeBuildRootDirectory(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) throws -> URL {
        try runtimeScratchRootDirectory()
            .appendingPathComponent(
                runtimeBuildCacheKey(target: target, configuration: configuration),
                isDirectory: true
            )
    }

    private static func runtimeBuildCacheDirectoryComponent(target: TargetTriple) -> String {
        targetTripleString(target)
    }

    static func swiftBuildArguments(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) throws -> [String] {
        try swiftBuildArguments(
            target: target, configuration: configuration,
            scratchDirectory: runtimeBuildScratchDirectory(target: target, configuration: configuration)
        )
    }

    private static func swiftBuildArguments(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration,
        scratchDirectory: URL
    ) -> [String] {
        // Never pass --disable-sandbox: the SwiftPM sandbox is a second layer
        // of containment behind the verified package root and keeps any
        // unexpected build-time tool from running unconstrained (KUU-788).
        var arguments = [
            "build",
            "-c", configuration.rawValue,
            "--target", "Runtime",
            "--disable-code-coverage",
            "--scratch-path", scratchDirectory.path,
        ]
        if target != TargetTriple.hostDefault() {
            arguments.append(contentsOf: ["--triple", targetTripleString(target)])
        }
        return arguments
    }

    private static func runtimeScratchRootDirectory() throws -> URL {
        runtimeSharedScratchRoot()
    }

    /// Runtime objects are keyed by a content hash of the Runtime sources (see
    /// `runtimeSourceFingerprint`), not by checkout location, so one cache
    /// directory is shared by every worktree: a fresh worktree whose Runtime
    /// sources are unchanged reuses the objects instead of paying a full
    /// from-scratch `swift build`. `KSWIFTK_RUNTIME_CACHE_DIR` overrides it.
    /// Exposed for testing and for `incrementalEnvironmentFingerprint`.
    static func runtimeSharedScratchRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let override = environment["KSWIFTK_RUNTIME_CACHE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let cachesBase: URL
#if canImport(Darwin)
        cachesBase = homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
#else
        if let xdg = environment["XDG_CACHE_HOME"], !xdg.isEmpty {
            cachesBase = URL(fileURLWithPath: xdg, isDirectory: true)
        } else {
            cachesBase = homeDirectory.appendingPathComponent(".cache", isDirectory: true)
        }
#endif
        return cachesBase
            .appendingPathComponent("kswiftk", isDirectory: true)
            .appendingPathComponent("runtime-build", isDirectory: true)
    }

    private static func withRuntimeBuildLock<T>(cacheKey: String, scratchRoot: URL, body: () throws -> T) throws -> T {
        let lockDirectory = scratchRoot.appendingPathComponent("locks", isDirectory: true)
        try FileManager.default.createDirectory(at: lockDirectory, withIntermediateDirectories: true)

        let lockURL = lockDirectory.appendingPathComponent("\(cacheKey).lock")
        let descriptor = lockURL.path.withCString { path in
            open(path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(systemErrorDescription("open"))
        }
        defer { close(descriptor) }

        guard flock(descriptor, LOCK_EX) == 0 else {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(systemErrorDescription("flock"))
        }
        defer { _ = flock(descriptor, LOCK_UN) }

        return try body()
    }

    // Runtime objects are only ever built from a compiler-owned, verified
    // KSwiftK package root. The process working directory is deliberately not
    // a candidate: it belongs to the project being compiled, and an
    // attacker-controlled Package.swift found there would be evaluated —
    // together with its build plugins — with the compiler user's privileges
    // before any Kotlin output runs (KUU-788).
    static func runtimePackageRootURL(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        // KSWIFTK_PACKAGE_ROOT is an explicit development override, so a value
        // that resolves to nothing or fails verification is rejected loudly
        // rather than silently falling through to an implicit root.
        if let overridePath = environment["KSWIFTK_PACKAGE_ROOT"], !overridePath.isEmpty {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            guard let candidate = firstAncestorContainingPackage(startingAt: overrideURL) else {
                throw CodegenRuntimeSupportError.runtimePackageRootUnavailable(
                    "KSWIFTK_PACKAGE_ROOT '\(overridePath)' has no Package.swift in its directory or ancestors"
                )
            }
            guard let rejection = runtimePackageRootRejection(candidate) else {
                return candidate
            }
            throw CodegenRuntimeSupportError.untrustedRuntimePackageRoot(
                "KSWIFTK_PACKAGE_ROOT '\(overridePath)' resolved to '\(candidate.path)', which failed verification: \(rejection)"
            )
        }

        var firstRejection: String?
        for searchStart in runtimePackageRootSearchStarts() {
            guard let candidate = firstAncestorContainingPackage(startingAt: searchStart) else {
                continue
            }
            if let rejection = runtimePackageRootRejection(candidate) {
                if firstRejection == nil {
                    firstRejection = "'\(candidate.path)': \(rejection)"
                }
                continue
            }
            return candidate
        }

        if let firstRejection {
            throw CodegenRuntimeSupportError.runtimePackageRootUnavailable(
                "the discovered package root was rejected: \(firstRejection)"
            )
        }
        throw CodegenRuntimeSupportError.runtimePackageRootUnavailable(
            "no Package.swift was found near the kswiftc executable or its build-time source path"
        )
    }

    // Anchors whose ancestors are searched for the compiler-owned package
    // root, in priority order: the real executable path — not
    // CommandLine.arguments[0], which a launcher can rewrite — then the
    // build-time source path embedded via #filePath. Exposed for testing.
    static func runtimePackageRootSearchStarts(
        executableURL: URL? = currentExecutableURL()
    ) -> [URL] {
        var starts: [URL] = []
        if let executableURL {
            starts.append(executableURL.deletingLastPathComponent())
        }
        starts.append(runtimeSourceCheckoutRootURL)
        return starts
    }

    // <repo>/Sources/CompilerBackend/<this file>, so three components up is
    // the checkout the compiler itself was built from. Exposed for testing.
    static let runtimeSourceCheckoutRootURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func currentExecutableURL() -> URL? {
#if canImport(Darwin)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var length = UInt32(buffer.count)
        guard _NSGetExecutablePath(&buffer, &length) == 0 else {
            return nil
        }
        return buffer.withUnsafeBufferPointer {
            URL(fileURLWithPath: String(cString: $0.baseAddress!))
        }
#elseif os(Linux)
        return URL(fileURLWithPath: "/proc/self/exe").resolvingSymlinksInPath()
#else
        return nil
#endif
    }

    // A package root may drive `swift build` only when it is verifiably the
    // KSwiftK package and nothing in the manifest or the Runtime source tree
    // can be tampered with by an unrelated local user: every checked path
    // must be owned by the current user or root and must not be writable by
    // others. Group-write stays allowed — shared checkouts are a normal dev
    // layout and ownership still bounds who can modify the tree. Exposed for
    // testing.
    static func runtimePackageRootRejection(_ root: URL) -> String? {
        let fileManager = FileManager.default
        if let reason = untrustedPathRejection(root.path, fileManager: fileManager) {
            return reason
        }

        let manifestURL = root.appendingPathComponent("Package.swift")
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: manifestURL.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return "no Package.swift manifest"
        }
        if let reason = untrustedPathRejection(manifestURL.path, fileManager: fileManager) {
            return reason
        }
        guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8),
              manifest.range(of: #"name:\s*"KSwiftK""#, options: .regularExpression) != nil else {
            return "Package.swift is not the KSwiftK package manifest"
        }

        for component in ["Sources/Runtime", "Sources/RuntimeABI", "Sources/RuntimeCAtomics", "Sources/CSQLite"] {
            let directoryURL = root.appendingPathComponent(component, isDirectory: true)
            var directoryFlag: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryURL.path, isDirectory: &directoryFlag),
                  directoryFlag.boolValue else {
                return "missing Runtime source directory '\(component)'"
            }
            if let reason = untrustedPathRejection(directoryURL.path, fileManager: fileManager) {
                return reason
            }
            // A writable directory is enough to flag the tree, but a stray
            // writable file inside a locked-down directory is just as
            // replaceable-by-edit, so verify every entry as well.
            guard let enumerator = fileManager.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return "cannot enumerate '\(component)'"
            }
            for case let entryURL as URL in enumerator {
                if let reason = untrustedPathRejection(entryURL.path, fileManager: fileManager) {
                    return reason
                }
            }
        }
        return nil
    }

    // Rejects a path whose attributes cannot be read (fail closed), whose
    // owner is neither the current user nor root, or that other users can
    // write to.
    private static func untrustedPathRejection(_ path: String, fileManager: FileManager) -> String? {
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? fileManager.attributesOfItem(atPath: resolvedPath) else {
            return "'\(path)': attributes could not be read"
        }
        guard let owner = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value,
              owner == 0 || owner == getuid() else {
            return "'\(path)': not owned by the current user or root"
        }
        guard let permissions = (attributes[.posixPermissions] as? NSNumber)?.uint16Value,
              permissions & 0o002 == 0 else {
            return "'\(path)': writable by other users"
        }
        return nil
    }

    private static func firstAncestorContainingPackage(startingAt url: URL) -> URL? {
        var current = url.standardizedFileURL
        let fileManager = FileManager.default
        while true {
            if fileManager.fileExists(atPath: current.appendingPathComponent("Package.swift").path) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                return nil
            }
            current = parent
        }
    }

    private static func runtimeBuildScratchDirectory(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) throws -> URL {
        try runtimeBuildRootDirectory(target: target, configuration: configuration)
    }

    static func runtimeBuildCacheKey(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) throws -> String {
        try runtimeBuildCacheKey(target: target, configuration: configuration, packageRoot: runtimePackageRootURL())
    }

    private static func runtimeBuildCacheKey(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration,
        packageRoot: URL
    ) throws -> String {
        "runtime-nocov-v4-\(configuration.rawValue)-\(targetTripleString(target))-\(try runtimeSourceFingerprint(packageRoot: packageRoot))"
    }

    // Hashes file contents under package-relative paths so the key is identical
    // across worktrees holding the same Runtime sources. RuntimeABI is part of
    // the linked object set, so it participates in the key too.
    private static func runtimeSourceFingerprint(packageRoot: URL) throws -> String {
        let sourcesURL = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        var payload = ""
        for module in ["Runtime", "RuntimeABI"] {
            let moduleURL = sourcesURL.appendingPathComponent(module, isDirectory: true)
            guard let enumerator = FileManager.default.enumerator(
                at: moduleURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                payload.append("\(module)-sources-missing\u{1}")
                continue
            }
            let modulePrefix = moduleURL.standardizedFileURL.path + "/"
            let files = (enumerator.allObjects as? [URL] ?? [])
                .filter { $0.pathExtension == "swift" }
                .sorted { $0.path < $1.path }
            payload.reserveCapacity(payload.count + files.count * 256)
            for fileURL in files {
                let fullPath = fileURL.standardizedFileURL.path
                let relativePath = fullPath.hasPrefix(modulePrefix)
                    ? String(fullPath.dropFirst(modulePrefix.count))
                    : fileURL.lastPathComponent
                payload.append(module)
                payload.append("/")
                payload.append(relativePath)
                payload.append("\u{0}")
                if let data = try? Data(contentsOf: fileURL) {
                    payload.append(String(decoding: data, as: UTF8.self))
                }
                payload.append("\u{1}")
            }
        }
        return stableFNV1a64Hex(payload)
    }

    private static func systemErrorDescription(_ operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }
}
