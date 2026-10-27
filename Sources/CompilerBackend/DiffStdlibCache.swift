import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Content-addressed stdlib resolution for repeated local diff invocations.
/// The ordinary compiler's packaged and explicit-artifact shortcuts are not
/// used here: a diff must match this compiler and its bundled sources.
public enum DiffStdlibCache {
    public enum Error: Swift.Error, CustomStringConvertible {
        case fingerprintUnavailable
        case inputsChangedDuringBuild
        case cacheDirectoryUnavailable

        public var description: String {
            switch self {
            case .fingerprintUnavailable:
                return "compiler, bundled stdlib, or loaded-library identity is unavailable"
            case .inputsChangedDuringBuild:
                return "compiler, bundled stdlib, or loaded-library inputs changed during the build"
            case .cacheDirectoryUnavailable:
                return "the user's standard caches directory is unavailable"
            }
        }
    }

    public static func resolve() throws -> String {
        guard let identity = currentFingerprint() else { throw Error.fingerprintUnavailable }
        let fm = FileManager.default
        let environment = ProcessInfo.processInfo.environment
        let directory: URL
        if let override = environment["KSWIFTK_STDLIB_CACHE_DIR"], !override.isEmpty {
            directory = URL(fileURLWithPath: override)
        } else if let userCache = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directory = userCache
        } else {
            throw Error.cacheDirectoryUnavailable
        }
        let target = TargetTriple.hostDefault()
        let path = try StdlibArtifactCache.resolveOrBuildCached(
            target: target,
            cacheDirectory: directory,
            compilerFingerprint: "diff-v1-\(identity)",
            preserveInvalidArtifacts: true,
            additionalValidator: { isIntactArtifact(at: $0) }
        ) { outputBase in
            // Keep the artifact independent of Runtime sources and the host
            // linker; the ordinary link phase resolves those inputs separately.
            let path = try StdlibArtifactBuilder.build(outputBase: outputBase, target: target)
            guard currentFingerprint() == identity else { throw Error.inputsChangedDuringBuild }
            try sealArtifact(at: path)
            return path
        }
        guard currentFingerprint() == identity else { throw Error.inputsChangedDuringBuild }
        return path
    }

    private static let integrityFile = ".kswiftk-diff-integrity.json"

    static func sealArtifact(at path: String) throws {
        let entries = try artifactDigests(at: path)
        let data = try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
        try data.write(to: URL(fileURLWithPath: path).appendingPathComponent(integrityFile), options: .atomic)
    }

    static func isIntactArtifact(at path: String) -> Bool {
        let file = URL(fileURLWithPath: path).appendingPathComponent(integrityFile)
        guard let data = try? Data(contentsOf: file),
              let expected = (try? JSONSerialization.jsonObject(with: data)) as? [String: String],
              let actual = try? artifactDigests(at: path)
        else { return false }
        return expected == actual
    }

    private static func artifactDigests(at path: String) throws -> [String: String] {
        let fm = FileManager.default
        // Foundation's directory enumerator can return /private/var paths
        // even when resolvingSymlinksInPath() retains /var on macOS.
        guard let resolved = realpath(path, nil) else { throw Error.fingerprintUnavailable }
        defer { free(resolved) }
        let root = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
        let prefix = root.path + "/"
        var enumerationFailed = false
        guard let enumerator = fm.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            errorHandler: { _, _ in enumerationFailed = true; return false }
        ) else { throw Error.fingerprintUnavailable }
        var result: [String: String] = [:]
        for case let file as URL in enumerator {
            let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true, file.path.hasPrefix(prefix) else {
                throw Error.fingerprintUnavailable
            }
            if properties.isDirectory == true { continue }
            guard properties.isRegularFile == true else { throw Error.fingerprintUnavailable }
            let relative = String(file.path.dropFirst(prefix.count))
            if relative == integrityFile { continue }
            guard let digest = digestFile(at: file.path) else {
                throw Error.fingerprintUnavailable
            }
            result[relative] = digest
        }
        guard !enumerationFailed, !result.isEmpty else { throw Error.fingerprintUnavailable }
        return result
    }

    static func currentFingerprint() -> String? {
        guard let executable = Bundle.main.executableURL?.resolvingSymlinksInPath().path,
              let sources = try? BundledStdlib.sourceFingerprint(),
              let llvm = LLVMCAPIBindings.loadUsable(),
              let loadedLibraries = DiffLoadedLibraries.current(excluding: executable)
        else { return nil }
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: executable) else { return nil }
        var dependencies = loadedLibraries
        if !dependencies.contains(where: { $0.0 == llvm.libraryPath }) {
            guard let llvmIdentity = dependencyIdentity(path: llvm.libraryPath) else { return nil }
            dependencies.append(llvmIdentity)
        }
        dependencies.sort { $0.0 < $1.0 }
        return fingerprint(
            executable: executable,
            sources: sources,
            dependencies: dependencies,
            environment: ProcessInfo.processInfo.environment,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    static func dependencyIdentity(path: String) -> (String, String)? {
        guard let digest = digestFile(at: path) else { return nil }
        return (path, digest)
    }

    private static func digestFile(at path: String) -> String? {
        guard let bytes = try? Data(contentsOf: URL(fileURLWithPath: path), options: [.mappedIfSafe]) else {
            return nil
        }
        return FileFingerprint.compute(for: path, contents: bytes).contentHash
    }

    /// Each field is length-delimited before hashing so arbitrary environment
    /// values or paths cannot produce ambiguous identities.
    static func fingerprint(
        executable: String,
        sources: String,
        dependencies: [(String, String)],
        environment: [String: String],
        operatingSystem: String
    ) -> String? {
        guard let executableHash = digestFile(at: executable) else { return nil }
        var data = Data()
        func append(_ value: String) {
            let bytes = Data(value.utf8)
            data.append(Data("\(bytes.count):".utf8))
            data.append(bytes)
        }
        append("diff-stdlib-cache-v1")
        append(executableHash)
        append(sources)
        append(operatingSystem)
        for (path, identity) in dependencies {
            append(path)
            append(identity)
        }
        for key in environment.keys.sorted() {
            append(key)
            append(environment[key] ?? "")
        }
        return FileFingerprint.compute(for: "diff-stdlib-cache", contents: data).contentHash
    }
}
