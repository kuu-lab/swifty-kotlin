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

    var description: String {
        switch self {
        case let .runtimeObjectsUnavailable(path):
            "Unable to locate packaged runtime object files under \(path)."
        case let .runtimeBuildFailed(reason):
            "Failed to build packaged runtime objects: \(reason)"
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
        let cacheKey = runtimeBuildCacheKey(target: target, configuration: configuration)
        return try runtimeObjectCache.getOrLoad(cacheKey: cacheKey) {
            try withRuntimeBuildLock(cacheKey: cacheKey) {
                // A non-empty scratch directory is NOT proof of a complete
                // runtime build: a killed kswiftc can leave its child
                // `swift build` orphaned and still writing objects, and an
                // interrupted build leaves a partial set behind. Linking a
                // partial set fails later with undefined `kk_*` symbols, so a
                // scratch cache hit requires the manifest written only after
                // a build completed under this lock.
                let manifestURL = runtimeObjectsManifestURL(target: target, configuration: configuration)
                let discovered = manifestValidatedRuntimeObjectPaths(manifestURL: manifestURL)
                if !discovered.isEmpty {
                    return discovered
                }

                try buildRuntimeObjects(target: target, configuration: configuration)

                let built = discoverScratchRuntimeObjectPaths(target: target, configuration: configuration)
                if !built.isEmpty {
                    try writeRuntimeObjectsManifest(built, to: manifestURL)
                    return built
                }

                let fallback = discoverPackageBuildRuntimeObjectPaths(target: target, configuration: configuration)
                guard !fallback.isEmpty else {
                    throw CodegenRuntimeSupportError.runtimeObjectsUnavailable(
                        runtimeBuildDirectory(target: target, configuration: configuration).path
                    )
                }
                return fallback
            }
        }
    }

    private static func buildRuntimeObjects(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) throws {
        let swiftPath = CommandRunner.resolveExecutable("swift", fallback: "/usr/bin/swift")
        do {
            _ = try CommandRunner.run(
                executable: swiftPath,
                arguments: swiftBuildArguments(target: target, configuration: configuration),
                currentDirectoryPath: packageRootURL().path,
                phaseTimer: nil,
                subPhaseName: "Link/swift-runtime-build",
                timeout: 300
            )
        } catch let error as CommandRunnerError {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(describeBuild(error))
        } catch {
            throw CodegenRuntimeSupportError.runtimeBuildFailed(String(describing: error))
        }
    }

    private static func describeBuild(_ error: CommandRunnerError) -> String {
        switch error {
        case let .launchFailed(reason):
            return reason
        case let .nonZeroExit(result):
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return stderr.isEmpty ? "swift build exited with code \(result.exitCode)." : stderr
        case let .timedOut(reason):
            return reason
        }
    }

    private static func discoverScratchRuntimeObjectPaths(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) -> [String] {
        discoverRuntimeObjectPaths(
            inScratchBuildDirectory: runtimeBuildDirectory(target: target, configuration: configuration),
            scratchRootDirectory: runtimeBuildRootDirectory(target: target, configuration: configuration)
        )
    }

    private static func runtimeObjectsManifestURL(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) -> URL {
        runtimeBuildRootDirectory(target: target, configuration: configuration)
            .appendingPathComponent("objects-\(configuration.rawValue).manifest")
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
        configuration: RuntimeBuildConfiguration
    ) -> [String] {
        let packageBuildRoot = packageRootURL()
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
            return candidates
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
                return candidates
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
    // belonging to other targets.
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
    // "RuntimeABI.o"), or the AST-wrapper debug object SwiftPM emits under
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

        return entries
            .filter { wholeModuleRuntimeObjectNames.contains($0.lastPathComponent) }
            .map(\.path)
            .sorted()
    }

    static func runtimeBuildDirectory(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) -> URL {
        runtimeBuildScratchDirectory(target: target, configuration: configuration)
            .appendingPathComponent(runtimeBuildCacheDirectoryComponent(target: target), isDirectory: true)
            .appendingPathComponent(configuration.rawValue, isDirectory: true)
            .appendingPathComponent("Runtime.build", isDirectory: true)
    }

    private static func runtimeBuildRootDirectory(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) -> URL {
        runtimeScratchRootDirectory()
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
    ) -> [String] {
        var arguments = [
            "build",
            "-c", configuration.rawValue,
            "--target", "Runtime",
            "--disable-code-coverage",
            "--disable-sandbox",
            "--scratch-path", runtimeBuildScratchDirectory(target: target, configuration: configuration).path,
        ]
        if target != TargetTriple.hostDefault() {
            arguments.append(contentsOf: ["--triple", targetTripleString(target)])
        }
        return arguments
    }

    private static func runtimeScratchRootDirectory() -> URL {
        packageRootURL().appendingPathComponent(".runtime-build", isDirectory: true)
    }

    private static func withRuntimeBuildLock<T>(cacheKey: String, body: () throws -> T) throws -> T {
        let lockDirectory = runtimeScratchRootDirectory().appendingPathComponent("locks", isDirectory: true)
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

    private static func packageRootURL() -> URL {
        if let overridePath = ProcessInfo.processInfo.environment["KSWIFTK_PACKAGE_ROOT"] {
            let overrideURL = URL(fileURLWithPath: overridePath, isDirectory: true)
            if let root = firstAncestorContainingPackage(startingAt: overrideURL) {
                return root
            }
        }

        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        if let root = firstAncestorContainingPackage(startingAt: currentDirectoryURL) {
            return root
        }

        if let executablePath = CommandLine.arguments.first, !executablePath.isEmpty {
            let executableURL = URL(fileURLWithPath: executablePath)
            if let root = firstAncestorContainingPackage(startingAt: executableURL.deletingLastPathComponent()) {
                return root
            }
        }

        let sourceRootURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return firstAncestorContainingPackage(startingAt: sourceRootURL) ?? sourceRootURL
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
    ) -> URL {
        runtimeBuildRootDirectory(target: target, configuration: configuration)
    }

    static func runtimeBuildCacheKey(
        target: TargetTriple,
        configuration: RuntimeBuildConfiguration
    ) -> String {
        "runtime-nocov-v2-\(configuration.rawValue)-\(targetTripleString(target))-\(runtimeSourceFingerprint())"
    }

    private static func runtimeSourceFingerprint() -> String {
        let runtimeSourcesURL = packageRootURL()
            .appendingPathComponent("Sources", isDirectory: true)
            .appendingPathComponent("Runtime", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: runtimeSourcesURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return "runtime-sources-missing"
        }

        let files = (enumerator.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.path < $1.path }

        var payload = ""
        payload.reserveCapacity(files.count * 256)
        for fileURL in files {
            payload.append(fileURL.path)
            payload.append("\u{0}")
            if let data = try? Data(contentsOf: fileURL) {
                payload.append(String(decoding: data, as: UTF8.self))
            }
            payload.append("\u{1}")
        }
        return stableFNV1a64Hex(payload)
    }

    private static func systemErrorDescription(_ operation: String) -> String {
        "\(operation) failed: \(String(cString: strerror(errno)))"
    }
}
