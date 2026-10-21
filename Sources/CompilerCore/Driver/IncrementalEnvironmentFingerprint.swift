import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Fingerprints inputs that can change the emitted artifact without touching
/// source files or CLI flags: the compiler binary itself, environment
/// variables that steer tool resolution and codegen, libraries visible
/// through the search paths, and resolved `-l` link inputs. The result is
/// folded into the incremental build-configuration hash, so a toolchain or
/// library change becomes a cache miss instead of restoring output built
/// against stale inputs.
enum IncrementalEnvironmentFingerprint {
    /// Environment variables consulted while locating the toolchain or the
    /// LLVM support library. `KSWIFTK_`- and `SWIFT_`-prefixed variables are
    /// included automatically on top of this list.
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

    /// Tools resolved through PATH by backend phases or the linker driver.
    private static let resolvedToolNames = ["swift", "swiftc", "clang", "dsymutil"]

    /// Binary/environment/tool-identity pieces that cannot change within one
    /// process lifetime, memoized so repeated compiles (test suites) do not
    /// re-walk PATH and re-stat the toolchain on every build.
    nonisolated(unsafe) private static var cachedStaticFingerprint:
        (environment: [String: String], parts: [String])?

    static func fingerprint(
        for options: CompilerOptions,
        environment: [String: String]
    ) -> [String] {
        var parts = staticFingerprint(environment: environment)

        // Imported .kklib libraries feed both Sema metadata and link inputs.
        for searchPath in options.effectiveLibrarySearchPaths {
            for kklib in kklibEntries(in: searchPath) {
                parts.append("kklib=\(kklib)|\(kklibFingerprint(kklib) ?? "unreadable")")
            }
        }

        // Resolved files for each -l library requested on the command line.
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

    /// Signature of the running compiler executable's real path, so different
    /// builds of the same version never share a cache entry.
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

    /// Stat-based signature of a single file: real path, size, mtime, inode
    /// and permissions — the same identity the linker-plan cache uses.
    static func signature(of path: String) -> String? {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: resolved) else {
            return nil
        }
        return [
            resolved,
            String(describing: attributes[.size]),
            String(describing: (attributes[.modificationDate] as? Date)?.timeIntervalSince1970),
            String(describing: attributes[.systemFileNumber]),
            String(describing: attributes[.posixPermissions]),
        ].joined(separator: "\u{0}")
    }

    /// `.kklib` library directories directly under a search path — the same
    /// set `discoverLibraryObjects` links against.
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
        // Fallback layout used when the manifest does not list objects.
        let objectsDir = root.appendingPathComponent("objects").path
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: objectsDir) {
            for entry in entries.filter({ $0.hasSuffix(".o") }).sorted() {
                parts.append("obj:\(entry)=\(signature(of: objectsDir + "/" + entry) ?? "missing")")
            }
        }
        return parts.joined(separator: "\u{1}")
    }

    /// Files the linker would resolve for `-l<name>`: `lib<name>.so`,
    /// `lib<name>.a`, plus the Darwin variants, in each `-L` directory.
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
