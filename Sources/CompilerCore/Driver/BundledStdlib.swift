import Foundation

/// `.kt` files under `Sources/CompilerCore/Stdlib/` are copied into the
/// `CompilerCore` resource bundle and injected as virtual `__bundled_*.kt`
/// source files before compilation. This type enumerates those resources and
/// computes a stable manifest hash used by incremental builds and stdlib
/// artifact validation.
package enum BundledStdlib {
    /// Errors that can occur while loading bundled stdlib sources from the
    /// resource bundle. These are converted to `KSWIFTK-SOURCE-0101`/`0102`
    /// diagnostics by `LoadSourcesPhase.injectBundledStdlib`.
    internal enum LoadError: Error, CustomStringConvertible {
        case resourcePathMissing
        case resourceDirectoryMissing(path: String)
        case enumerationFailed(path: String)
        case readFailed(path: String)

        var description: String {
            switch self {
            case .resourcePathMissing:
                return "Bundled stdlib resources are missing: resource path is not available."
            case .resourceDirectoryMissing(let path):
                return "Bundled stdlib resource directory not found: \(path)"
            case .enumerationFailed(let path):
                return "Failed to enumerate bundled stdlib resources at \(path)."
            case .readFailed(let path):
                return "Failed to read bundled stdlib source: \(path)"
            }
        }
    }

    internal static func collectBundledStdlibSources(
        resourcePath: String? = Bundle.module.resourcePath,
        profile: StdlibProfile = .full
    ) throws -> [(path: String, contents: Data)] {
        guard let resourcePath else {
            throw LoadError.resourcePathMissing
        }

        let stdlibDir = (resourcePath as NSString).appendingPathComponent("Stdlib")
        let fm = FileManager.default

        var isDirectory: ObjCBool = false
        let dirExists = fm.fileExists(atPath: stdlibDir, isDirectory: &isDirectory) && isDirectory.boolValue
        guard dirExists else {
            throw LoadError.resourceDirectoryMissing(path: stdlibDir)
        }

        guard let enumerator = fm.enumerator(atPath: stdlibDir) else {
            throw LoadError.enumerationFailed(path: stdlibDir)
        }

        var relativePaths: [String] = []
        while let path = enumerator.nextObject() as? String {
            if path.hasSuffix(".kt"), !path.hasPrefix("jvm/") {
                relativePaths.append(String(path.dropLast(3)))
            }
        }
        relativePaths.sort()

        var bundledSources: [(path: String, contents: Data)] = []
        for relativePath in relativePaths {
            let bundledPath = "__bundled_\(relativePath).kt"
            let fullPath = (stdlibDir as NSString).appendingPathComponent(relativePath + ".kt")
            guard let data = fm.contents(atPath: fullPath) else {
                throw LoadError.readFailed(path: fullPath)
            }
            if profile != .full,
               !profile.includes(package: StdlibProfile.declaredPackage(in: data))
            {
                continue
            }
            bundledSources.append((path: bundledPath, contents: data))
        }

        return bundledSources.sorted(by: { $0.path < $1.path })
    }

    /// Per-profile source and hash cache. Profiles are computed on first use so
    /// a compile that never asks for `minimal` pays nothing for it.
    private final class ProfileCache: @unchecked Sendable {
        private let lock = NSLock()
        private var sources: [StdlibProfile: [(path: String, contents: Data)]] = [:]
        private var hashes: [StdlibProfile: String] = [:]

        func sources(for profile: StdlibProfile) -> [(path: String, contents: Data)] {
            lock.lock()
            defer { lock.unlock() }
            if let cached = sources[profile] { return cached }
            let loaded = (try? BundledStdlib.collectBundledStdlibSources(profile: profile)) ?? []
            sources[profile] = loaded
            return loaded
        }

        func hash(for profile: StdlibProfile) -> String {
            let loaded = sources(for: profile)
            lock.lock()
            defer { lock.unlock() }
            if let cached = hashes[profile] { return cached }
            // Rebuild artifacts predating metadata or callback ABI changes. The
            // profile is part of the hash so a minimal artifact can never
            // validate as full (or the reverse); the full profile keeps the
            // pre-profile hash input.
            var hashed = loaded + [
                (path: "__metadata_visibility_v2", contents: Data()),
                (path: "__metadata_callback_abi_v1", contents: Data()),
            ]
            if profile != .full {
                hashed.append((path: "__stdlib_profile_\(profile.rawValue)", contents: Data()))
            }
            let value = BundledStdlib.manifestHash(for: hashed)
            hashes[profile] = value
            return value
        }
    }

    private static let profileCache = ProfileCache()

    /// Returns the bundled stdlib sources of `profile` as (virtualPath, contents)
    /// pairs in a deterministic order. This matches the sources injected by
    /// `LoadSourcesPhase` and is used to compute the stdlib manifest hash for
    /// incremental builds.
    package static func bundledStdlibSources(
        profile: StdlibProfile = .full
    ) -> [(path: String, contents: Data)] {
        profileCache.sources(for: profile)
    }

    package static func manifestHash(profile: StdlibProfile = .full) -> String {
        profileCache.hash(for: profile)
    }

    /// Packages declared by the full profile that `profile` leaves out, as
    /// sorted dotted names. Used to explain a missing import precisely.
    package static func excludedPackages(for profile: StdlibProfile) -> [String] {
        guard profile != .full else { return [] }
        let kept = Set(bundledStdlibSources(profile: profile).map {
            StdlibProfile.declaredPackage(in: $0.contents)
        })
        let all = Set(bundledStdlibSources(profile: .full).map {
            StdlibProfile.declaredPackage(in: $0.contents)
        })
        return all.subtracting(kept).sorted()
    }

    private static func manifestHash(for sources: [(path: String, contents: Data)]) -> String {
        var hasher = StableFNV1a64.Hasher()
        for (path, contents) in sources {
            hasher.update(bytes: path.utf8)
            hasher.update(bytes: contents)
        }
        return hasher.hexString()
    }
}
