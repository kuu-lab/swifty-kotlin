import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

enum IncrementalEnvironmentFingerprint {
    private static let fixedEnvironmentKeys = [
        "DEVELOPER_DIR",
        "TOOLCHAINS",
        "SDKROOT",
        "MACOSX_DEPLOYMENT_TARGET",
        "PATH",
        "LIBRARY_PATH",
        "LD_LIBRARY_PATH",
        "DYLD_LIBRARY_PATH",
        "DYLD_FALLBACK_LIBRARY_PATH",
        "DYLD_IMAGE_SUFFIX",
        "HOME",
        "KOTLIN_HOME",
        "JAVA_HOME",
    ]

    private static let resolvedToolNames = ["swift", "swiftc", "clang", "dsymutil"]

    nonisolated(unsafe) private static var cachedStaticFingerprint:
        (environment: [String: String], parts: [String])?

    static func fingerprint(
        for options: CompilerOptions,
        environment: [String: String]
    ) -> [String] {
        var parts = staticFingerprint(environment: environment)

        for searchPath in options.effectiveLibrarySearchPaths {
            for kklib in kklibEntries(in: searchPath) {
                parts.append("kklib=\(kklib)|\(kklibFingerprint(kklib) ?? "unreadable")")
            }
        }

        for name in options.linkLibraries.sorted() {
            for file in resolvedLibraryFiles(name: name, libraryPaths: options.libraryPaths) {
                parts.append("lib:\(name)=\(file)|\(signature(of: file) ?? "missing")")
            }
        }

        return parts
    }

    private static func staticFingerprint(environment: [String: String]) -> [String] {
        if let cached = cachedStaticFingerprint, cached.environment == environment {
            return cached.parts
        }
        var parts = ["env-v1"]

        // The running binary's own signature catches rebuilds that keep the
        // same version string — without it a compiler fix could restore an
        // artifact produced by the previous binary.
        parts.append("executable=\(executableSignature() ?? "unavailable")")

        var keys = Set(fixedEnvironmentKeys)
        keys.formUnion(environment.keys.filter {
            $0.hasPrefix("KSWIFTK_") || $0.hasPrefix("SWIFT_")
        })
        for key in keys.sorted() {
            parts.append("env:\(key)=\(environment[key] ?? "")")
        }

        let pathEnvironment = environment["PATH"] ?? ""
        for tool in resolvedToolNames {
            let resolved = CommandRunner.resolveExecutable(
                tool, fallback: "", pathEnvironment: pathEnvironment
            )
            parts.append("tool:\(tool)=\(resolved)|\(signature(of: resolved) ?? "missing")")
        }

        cachedStaticFingerprint = (environment, parts)
        return parts
    }

    private static func executableSignature() -> String? {
#if canImport(Darwin)
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        var length = UInt32(buffer.count)
        guard _NSGetExecutablePath(&buffer, &length) == 0 else { return nil }
        return buffer.withUnsafeBufferPointer {
            signature(of: String(cString: $0.baseAddress!))
        }
#elseif os(Linux)
        return signature(of: "/proc/self/exe")
#else
        return nil
#endif
    }

    static func signature(of path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        // `attributesOfItem` pays several xattr syscalls per file; kklib
        // object signatures run on every incremental check, so a single
        // stat(2) gives the same fields (symlink-following, same as
        // attributesOfItem).
        var info = stat()
        guard resolved.withCString({ stat($0, &info) == 0 }) else {
            return nil
        }
        #if canImport(Darwin)
        let modificationDate = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
        )
        #else
        let modificationDate = Date(
            timeIntervalSince1970: TimeInterval(info.st_mtim.tv_sec)
                + TimeInterval(info.st_mtim.tv_nsec) / 1_000_000_000
        )
        #endif
        let size: Any? = NSNumber(value: info.st_size)
        let fileNumber: Any? = NSNumber(value: info.st_ino)
        let permissions: Any? = NSNumber(value: Int32(info.st_mode) & 0o7777)
        return [
            resolved,
            String(describing: size),
            String(describing: modificationDate.timeIntervalSince1970 as Double?),
            String(describing: fileNumber),
            String(describing: permissions),
        ].joined(separator: "\u{0}")
    }

    private static func kklibEntries(in searchPath: String) -> [String] {
        let path = URL(fileURLWithPath: searchPath).standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return []
        }
        if path.hasSuffix(".kklib") {
            return isDirectory.boolValue ? [path] : []
        }
        guard isDirectory.boolValue,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: path)
        else {
            return []
        }
        return entries
            .filter { $0.hasSuffix(".kklib") }
            .map { URL(fileURLWithPath: path).appendingPathComponent($0).standardizedFileURL.path }
            .sorted()
    }

    /// Content hash of the library manifest plus stat signatures of the
    /// object files it lists. The manifest hash alone would miss object
    /// bytes replaced under an unchanged manifest; signatures alone would
    /// miss manifest-only changes.
    private static func kklibFingerprint(_ kklibPath: String) -> String? {
        let root = URL(fileURLWithPath: kklibPath).resolvingSymlinksInPath().standardizedFileURL
        let manifestURL = root.appendingPathComponent("manifest.json")
        var parts: [String] = []
        if let data = try? Data(contentsOf: manifestURL) {
            parts.append("manifest=\(FileFingerprint.sha256Hex(data))")
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let objects = object["objects"] as? [String]
            {
                for entry in objects.sorted() {
                    let objectPath = root.appendingPathComponent(entry).standardizedFileURL.path
                    parts.append("obj:\(entry)=\(signature(of: objectPath) ?? "missing")")
                }
            }
        } else {
            parts.append("manifest=missing")
        }
        let objectsDir = root.appendingPathComponent("objects").path
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: objectsDir) {
            for entry in entries.filter({ $0.hasSuffix(".o") }).sorted() {
                parts.append("obj:\(entry)=\(signature(of: objectsDir + "/" + entry) ?? "missing")")
            }
        }
        return parts.joined(separator: "\u{1}")
    }

    private static func resolvedLibraryFiles(name: String, libraryPaths: [String]) -> [String] {
        let candidates = [
            "lib\(name).so", "lib\(name).a", "lib\(name).dylib", "lib\(name).tbd",
        ]
        var resolved: [String] = []
        for libraryPath in libraryPaths {
            let directory = URL(fileURLWithPath: libraryPath).standardizedFileURL.path
            for candidate in candidates {
                let fullPath = directory + "/" + candidate
                var isDirectory = ObjCBool(false)
                if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory),
                   !isDirectory.boolValue
                {
                    resolved.append(fullPath)
                }
            }
        }
        return resolved
    }
}
