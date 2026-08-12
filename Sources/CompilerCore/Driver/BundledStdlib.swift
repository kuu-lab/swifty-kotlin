import Foundation

/// Bundled stdlib source manifest and resource loading.
///
/// `.kt` files under `Sources/CompilerCore/Stdlib/` are copied into the
/// `CompilerCore` resource bundle and injected as virtual `__bundled_*.kt`
/// source files before compilation. This type enumerates those resources and
/// computes a stable manifest hash used by incremental builds and stdlib
/// artifact validation.
package enum BundledStdlib {
    /// Bundled `.kt` files under `Stdlib/` that are discovered by
    /// `LoadSourcesPhase` but should not be injected into the compilation.
    ///
    /// KSP-301: ghost entries (ResultExtensions, AdvancedLogger,
    /// KClassAnnotationRegistration, StringBasics, StringEncoding) were already
    /// removed from this list. KSP-312 wired RangeIterators and KSP-305 wires
    /// CollectionFactories, so no bundled stdlib files are currently excluded.
    static let excludedBundledStdlibFiles: Set<String> = [
    ]

    // Legacy empty inline source markers. The actual implementations have been
    // migrated to bundled `.kt` files under `Sources/CompilerCore/Stdlib/`.
    // count / any / all / none / contains / containsAll / lastIndexOf have been
    // migrated to ListSearchHOF.kt. sumOf / maxByOrNull / minByOrNull have been
    // migrated to ListAggregateHOF.kt (KSP-501). The remaining collection HOFs
    // (filter, sorting, set) are in ListFilterHOF.kt, ListSortingHOF.kt, and
    // SetHOF.kt respectively.
    static let kotlinCollectionsSource = ""

    // repeat / reversed / padStart / padEnd have been migrated to StringBasics.kt.
    // toByteArray / encodeToByteArray / decodeToString / Charsets have been migrated to
    // StringEncoding.kt (delegating to the __kk_-prefixed bridges in RuntimeStringEncoding.swift);
    // kotlinx.cinterop.ByteArray.toKString has been migrated to CInteropExtensions.kt.
    // indent / trimIndent / trimMargin / prependIndent / replaceIndent(ByMargin) have been
    // migrated to StringIndentFormat.kt. The case-conversion functions (lowercase, uppercase,
    // capitalize, replaceFirstChar, locale variants) have been migrated to StringCaseConversion.kt.
    static let kotlinTextSource = ""

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

    /// Collects bundled stdlib `.kt` sources from `resourcePath/Stdlib`.
    /// Throws `LoadError` when the resource path is missing, the `Stdlib`
    /// directory cannot be enumerated, or a `.kt` file cannot be read.
    internal static func collectBundledStdlibSources(
        resourcePath: String? = Bundle.module.resourcePath
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
            if path.hasSuffix(".kt") {
                relativePaths.append(String(path.dropLast(3)))
            }
        }
        relativePaths.sort()

        var bundledSources: [(path: String, contents: Data)] = []
        for relativePath in relativePaths {
            guard !Self.excludedBundledStdlibFiles.contains(relativePath) else { continue }
            let bundledPath = "__bundled_\(relativePath).kt"
            let fullPath = (stdlibDir as NSString).appendingPathComponent(relativePath + ".kt")
            guard let data = fm.contents(atPath: fullPath) else {
                throw LoadError.readFailed(path: fullPath)
            }
            bundledSources.append((path: bundledPath, contents: data))
        }

        return bundledSources.sorted(by: { $0.path < $1.path })
    }

    private static let _bundledStdlibSources: [(path: String, contents: Data)] =
        (try? Self.collectBundledStdlibSources()) ?? []

    /// Returns all bundled stdlib sources as (virtualPath, contents) pairs in a
    /// deterministic order. This matches the sources injected by `LoadSourcesPhase`
    /// and is used to compute the stdlib manifest hash for incremental builds.
    package static func bundledStdlibSources() -> [(path: String, contents: Data)] {
        _bundledStdlibSources
    }

    private static let _manifestHash: String = Self.stableFNV1a64Hex(for: _bundledStdlibSources)

    /// Returns a stable hash of the bundled stdlib manifest.
    package static func manifestHash() -> String {
        _manifestHash
    }

    private static func stableFNV1a64Hex(for sources: [(path: String, contents: Data)]) -> String {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for (path, contents) in sources {
            for byte in Data(path.utf8) {
                hash ^= UInt64(byte)
                hash &*= 0x100_0000_01B3
            }
            for byte in contents {
                hash ^= UInt64(byte)
                hash &*= 0x100_0000_01B3
            }
        }
        return String(format: "%016llx", hash)
    }
}
