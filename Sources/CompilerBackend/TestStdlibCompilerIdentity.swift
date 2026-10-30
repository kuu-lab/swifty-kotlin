import CompilerCore
import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Inputs that must match between a test process and its isolated stdlib builder.
public enum TestStdlibCompilerIdentity {
    /// Why ``current()`` could not produce an identity. ``currentWithDiagnostics()``
    /// surfaces the failing stage so CI logs name it instead of only reporting a
    /// missing fingerprint.
    public enum IdentityUnavailable: Error, CustomStringConvertible, Equatable {
        case injectedLibraries
        case llvmUnavailable
        case llvmIdentityUnavailable(String)
        case stdlibSourcesEmpty

        public var description: String {
            switch self {
            case .injectedLibraries:
                return "DYLD_INSERT_LIBRARIES is set"
            case .llvmUnavailable:
                return "no usable libLLVM could be loaded"
            case .llvmIdentityUnavailable(let detail):
                return "could not fingerprint the loaded LLVM/runtime images: \(detail)"
            case .stdlibSourcesEmpty:
                return "bundled stdlib sources are unavailable"
            }
        }
    }

    public static func current() -> String? {
        try? currentWithDiagnostics().get()
    }

    public static func currentWithDiagnostics() -> Result<String, IdentityUnavailable> {
        if let inserted = ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"], !inserted.isEmpty {
            return .failure(.injectedLibraries)
        }
        guard let llvm = LLVMCAPIBindings.loadUsable() else { return .failure(.llvmUnavailable) }
        #if canImport(Darwin)
        var info = Dl_info()
        guard dladdr(unsafeBitCast(llvm.contextCreateFn, to: UnsafeRawPointer.self), &info) != 0,
              let filename = info.dli_fname else {
            return .failure(.llvmIdentityUnavailable("dladdr could not locate the loaded libLLVM"))
        }
        let llvmPath = String(cString: filename)
        guard let llvmHash = stableFileHash(llvmPath) else {
            return .failure(.llvmIdentityUnavailable("could not hash \(llvmPath) (missing or changed while reading)"))
        }
        let llvmIdentity = "\(llvmPath)|\(llvmHash)"
        #elseif canImport(Glibc)
        // If the selected image cannot be queried portably, fingerprint every
        // candidate in search order and every loaded executable mapping.
        let linuxIdentity: Result<String, IdentityUnavailable> = withExtendedLifetime(llvm) {
            var files: [String: LinuxDigest] = [:]
            guard let candidates = candidateLibrariesFingerprint(files: &files) else {
                return .failure(.llvmIdentityUnavailable("a candidate library path failed to hash"))
            }
            switch linuxLoadedLibrariesFingerprint(files: &files) {
            case .failure(let reason):
                return .failure(reason)
            case .success(let loaded):
                guard files.allSatisfy({ linuxFileSignature($0.key) == $0.value.signature }) else {
                    return .failure(.llvmIdentityUnavailable("a fingerprinted file changed on disk"))
                }
                return .success("\(candidates)|\(loaded)")
            }
        }
        let llvmIdentity: String
        switch linuxIdentity {
        case .failure(let reason): return .failure(reason)
        case .success(let value): llvmIdentity = value
        }
        #else
        return .failure(.llvmIdentityUnavailable("unsupported platform"))
        #endif

        let sources = BundledStdlib.bundledStdlibSources()
        guard !sources.isEmpty else { return .failure(.stdlibSourcesEmpty) }
        var input = Data()
        func append(_ value: String) {
            let bytes = Data(value.utf8)
            input.append(Data("\(bytes.count):".utf8))
            input.append(bytes)
        }
        append("test-stdlib-worker-context-v1")
        append(ProcessInfo.processInfo.operatingSystemVersionString)
        let target = TargetTriple.hostDefault()
        append("\(target.arch)-\(target.vendor)-\(target.os)-\(target.osVersion ?? "")")
        append(llvmIdentity)
        for source in sources.sorted(by: { $0.path < $1.path }) {
            append(source.path)
            append(FileFingerprint.compute(for: source.path, contents: source.contents).contentHash)
        }
        append(environmentFingerprint(ProcessInfo.processInfo.environment))
        return .success(FileFingerprint.compute(for: "test-stdlib-worker-context", contents: input).contentHash)
    }

    #if canImport(Glibc)
    private struct LinuxFileSignature: Equatable {
        let device: UInt64
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
        let changedSeconds: Int64
        let changedNanoseconds: Int64
    }

    private struct LinuxDigest {
        let signature: LinuxFileSignature
        let digest: String
    }

    private static func linuxFileSignature(_ path: String) -> LinuxFileSignature? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return LinuxFileSignature(
            device: UInt64(info.st_dev), inode: UInt64(info.st_ino), size: Int64(info.st_size),
            modifiedSeconds: Int64(info.st_mtim.tv_sec), modifiedNanoseconds: Int64(info.st_mtim.tv_nsec),
            changedSeconds: Int64(info.st_ctim.tv_sec), changedNanoseconds: Int64(info.st_ctim.tv_nsec)
        )
    }

    private static func linuxDigest(_ path: String, files: inout [String: LinuxDigest]) -> String? {
        guard let before = linuxFileSignature(path) else { return nil }
        if let cached = files[path], cached.signature == before { return cached.digest }
        guard let digest = stableFileHash(path), linuxFileSignature(path) == before else { return nil }
        files[path] = LinuxDigest(signature: before, digest: digest)
        return digest
    }

    private static func candidateLibrariesFingerprint(files: inout [String: LinuxDigest]) -> String? {
        var input = Data()
        func append(_ value: String) {
            let bytes = Data(value.utf8)
            input.append(Data("\(bytes.count):".utf8))
            input.append(bytes)
        }
        for candidate in LLVMCAPIBindings.candidateLibraryPaths() {
            append(candidate)
            switch TrustedFileSystem.inspectLoadableFile(candidate) {
            case .trusted(let resolved):
                guard let digest = linuxDigest(resolved, files: &files) else { return nil }
                append("trusted")
                append(resolved)
                append(digest)
            case .rejected(let component, let reason):
                append("rejected")
                append(component)
                append(reason.diagnosticDetail)
            }
        }
        return FileFingerprint.compute(for: "test-stdlib-llvm-candidates", contents: input).contentHash
    }

    private static func linuxLoadedLibrariesFingerprint(
        files: inout [String: LinuxDigest]
    ) -> Result<String, IdentityUnavailable> {
        guard let maps = try? String(contentsOfFile: "/proc/self/maps", encoding: .utf8) else {
            return .failure(.llvmIdentityUnavailable("could not read /proc/self/maps"))
        }
        let paths: [String]
        switch linuxExecutableMappingsDetailed(maps) {
        case .failure(let reason): return .failure(reason)
        case .success(let value): paths = value
        }
        var input = Data()
        for path in paths {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard let digest = linuxDigest(resolved, files: &files) else {
                return .failure(.llvmIdentityUnavailable("could not hash \(resolved) (missing or changed while reading)"))
            }
            for value in [path, resolved, digest] {
                let bytes = Data(value.utf8)
                input.append(Data("\(bytes.count):".utf8))
                input.append(bytes)
            }
        }
        return .success(FileFingerprint.compute(for: "test-stdlib-linux-images", contents: input).contentHash)
    }
    #endif

    static func linuxExecutableMappings(_ maps: String) -> [String]? {
        try? linuxExecutableMappingsDetailed(maps).get()
    }

    private static func linuxExecutableMappingsDetailed(_ maps: String) -> Result<[String], IdentityUnavailable> {
        var paths: Set<String> = []
        for line in maps.split(separator: "\n") {
            let fields = line.split(maxSplits: 5, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 5 else {
                return .failure(.llvmIdentityUnavailable("malformed /proc/self/maps line: \(line.prefix(100))"))
            }
            guard fields[1].contains("x") else { continue }
            guard fields.count == 6 else {
                return .failure(.llvmIdentityUnavailable("anonymous executable mapping: \(line.prefix(100))"))
            }
            let path = String(fields[5])
            if path == "[vdso]" || path == "[vsyscall]" { continue }
            guard path.hasPrefix("/") else {
                return .failure(.llvmIdentityUnavailable("non-file executable mapping: \(path)"))
            }
            guard !path.hasSuffix(" (deleted)") else {
                return .failure(.llvmIdentityUnavailable("executable mapped from deleted file: \(path)"))
            }
            paths.insert(path)
        }
        return .success(paths.sorted())
    }

    static func environmentFingerprint(_ environment: [String: String]) -> String {
        // These identify the test request itself, not compiler inputs.
        let transientKeys: Set<String> = ["KSWIFTK_TEST_STDLIB_PROVENANCE", "CODEX_TOOL_CALL_ID"]
        var data = Data()
        func append(_ value: String) {
            let bytes = Data(value.utf8)
            data.append(Data("\(bytes.count):".utf8))
            data.append(bytes)
        }
        for key in environment.keys.sorted() where !transientKeys.contains(key) {
            append(key)
            append(environment[key] ?? "")
        }
        return FileFingerprint.compute(for: "test-stdlib-environment", contents: data).contentHash
    }

    private static func stableFileHash(_ path: String) -> String? {
        let fm = FileManager.default
        guard let before = try? fm.attributesOfItem(atPath: path),
              before[.type] as? FileAttributeType == .typeRegular,
              let changeBefore = fileChangeTime(path),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe)
        else { return nil }
        let digest = FileFingerprint.compute(for: path, contents: data).contentHash
        guard let changeAfter = fileChangeTime(path), changeBefore.0 == changeAfter.0,
              changeBefore.1 == changeAfter.1,
              let after = try? fm.attributesOfItem(atPath: path),
              (before[.size] as? NSNumber) == (after[.size] as? NSNumber),
              (before[.modificationDate] as? Date) == (after[.modificationDate] as? Date),
              (before[.systemFileNumber] as? NSNumber) == (after[.systemFileNumber] as? NSNumber)
        else { return nil }
        return digest
    }

    private static func fileChangeTime(_ path: String) -> (Int64, Int64)? {
        #if canImport(Darwin)
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (Int64(info.st_ctimespec.tv_sec), Int64(info.st_ctimespec.tv_nsec))
        #elseif canImport(Glibc)
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return (Int64(info.st_ctim.tv_sec), Int64(info.st_ctim.tv_nsec))
        #else
        return nil
        #endif
    }
}
