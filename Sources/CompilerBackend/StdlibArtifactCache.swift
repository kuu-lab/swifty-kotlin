import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Builds and locates the stdlib artifact used by the executable CLI path.
///
/// Packaged artifacts are preferred. When a package does not provide one, the
/// artifact is generated in the user's standard caches directory. The cache is
/// keyed by target and guarded by an advisory lock so parallel first launches
/// cannot publish a partial `.kklib`.
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
    private static let kotlinLanguageVersion = "2.3.10"
    private static let compilerVersion = "0.1.0"

    /// Resolve a packaged artifact or build one in the user's standard cache.
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

        let artifactURL = try cacheArtifactURL(for: target)
        let artifactPath = artifactURL.path
        let lockPath = artifactPath + ".lock"
        let fingerprintPath = artifactPath + ".compiler-fingerprint"
        try fileManager.createDirectory(
            at: artifactURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: nil
        )

        return try withFileLock(at: lockPath) {
            if case .valid = validateArtifact(at: artifactPath, target: target),
               fingerprintMatches(fingerprintPath: fingerprintPath)
            {
                return artifactPath
            }

            if fileManager.fileExists(atPath: artifactPath) {
                try fileManager.removeItem(atPath: artifactPath)
            }
            try? fileManager.removeItem(atPath: fingerprintPath)

            let buildingBase = artifactPath + ".building"
            let buildingArtifactPath = buildingBase + ".kklib"
            try? fileManager.removeItem(atPath: buildingBase)
            try? fileManager.removeItem(atPath: buildingArtifactPath)

            let builtArtifactPath: String
            do {
                builtArtifactPath = try StdlibArtifactBuilder.build(
                    outputBase: buildingBase,
                    target: target
                )
            } catch {
                try? fileManager.removeItem(atPath: buildingBase)
                try? fileManager.removeItem(atPath: buildingArtifactPath)
                throw Error.buildFailed(String(describing: error))
            }

            guard case .valid = validateArtifact(at: builtArtifactPath, target: target) else {
                throw Error.artifactInvalid(
                    path: builtArtifactPath,
                    reason: validationReason(at: builtArtifactPath, target: target)
                )
            }

            try fileManager.moveItem(atPath: builtArtifactPath, toPath: artifactPath)
            if let fingerprint = currentCompilerFingerprint() {
                try fingerprint.write(toFile: fingerprintPath, atomically: true, encoding: .utf8)
            }
            return artifactPath
        }
    }

    /// Candidate locations for artifacts installed next to `kswiftc`.
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

    private static func cacheArtifactURL(for target: TargetTriple) throws -> URL {
        guard let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            throw Error.cacheDirectoryUnavailable
        }

        let targetKey = [target.arch, target.vendor, target.os, target.osVersion ?? "none"]
            .map { component in
                component.replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "\\", with: "_")
            }
            .joined(separator: "-")
        return cachesURL
            .appendingPathComponent("kswiftk", isDirectory: true)
            .appendingPathComponent("stdlib", isDirectory: true)
            .appendingPathComponent("\(kotlinLanguageVersion)-\(compilerVersion)-\(targetKey)", isDirectory: true)
            .appendingPathComponent(artifactFileName, isDirectory: true)
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
        let rootURL = URL(fileURLWithPath: path).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return .invalid("artifact directory does not exist")
        }

        let manifestURL = rootURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return .invalid("manifest.json is missing")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let manifest = object as? [String: Any]
        else {
            return .invalid("manifest.json is not valid JSON")
        }

        guard let formatVersion = manifest["formatVersion"] as? Int,
              formatVersion == 1
        else {
            return .invalid("manifest formatVersion must be 1")
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
              let metadataURL = containedURL(relativePath: metadata, under: rootURL),
              fileManager.fileExists(atPath: metadataURL.path)
        else {
            return .invalid("metadata file is missing or escapes the artifact")
        }
        guard let inlineKIRDir = manifest["inlineKIRDir"] as? String,
              let inlineURL = containedURL(relativePath: inlineKIRDir, under: rootURL)
        else {
            return .invalid("inlineKIRDir is missing or escapes the artifact")
        }
        var inlineIsDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: inlineURL.path, isDirectory: &inlineIsDirectory), inlineIsDirectory.boolValue else {
            return .invalid("inline-KIR directory is missing")
        }

        guard let objects = manifest["objects"] as? [String], !objects.isEmpty else {
            return .invalid("manifest objects are missing")
        }
        for objectPath in objects {
            guard let objectURL = containedURL(relativePath: objectPath, under: rootURL),
                  fileManager.fileExists(atPath: objectURL.path)
            else {
                return .invalid("an object path is missing or escapes the artifact")
            }
        }

        return .valid
    }

    private static func containedURL(relativePath: String, under rootURL: URL) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        let candidate = rootURL.appendingPathComponent(relativePath).standardizedFileURL
        let rootPath = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        guard candidate.path.hasPrefix(rootPath) else { return nil }
        return candidate
    }

    private static func fingerprintMatches(fingerprintPath: String) -> Bool {
        guard let current = currentCompilerFingerprint(),
              let saved = try? String(contentsOfFile: fingerprintPath, encoding: .utf8)
        else {
            return false
        }
        return current == saved
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

    public static func build(outputBase: String, target: TargetTriple) throws -> String {
        let options = CompilerOptions(
            moduleName: "KSwiftKStdlib",
            inputs: [],
            outputPath: outputBase,
            emit: .library,
            target: target,
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
        return artifactPath
    }
}
