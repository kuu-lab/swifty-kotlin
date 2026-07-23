import Foundation

/// Residual bundled Kotlin source for stdlib functions not yet migrated to
/// standalone `.kt` files under `Sources/CompilerCore/Stdlib/`.
///
/// As functions are migrated to `.kt` files (auto-discovered by
/// `LoadSourcesPhase.injectBundledStdlib`), remove them from here.
enum BundledKotlinStdlib {
    /// Bundled `.kt` files under `Stdlib/` that are discovered by
    /// `LoadSourcesPhase` but should not be injected into the compilation.
    static let excludedBundledStdlibFiles: Set<String> = [
        // KSP-305: the source file exists but collection-factory lowering is not wired yet.
        "kotlin/collections/CollectionFactories",
    ]

    // count / any / all / none / sumOf / maxByOrNull / minByOrNull are not yet
    // in standalone .kt files. The remaining collection HOFs (search, aggregate,
    // filter, sorting, set) have been migrated to ListSearchHOF.kt,
    // ListAggregateHOF.kt, ListFilterHOF.kt, ListSortingHOF.kt, and SetHOF.kt
    // respectively.
    static let kotlinCollectionsSource = """
package kotlin.collections

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_list_of")
private external fun <T> __kk_list_of(array: Any?, count: Int): MutableList<T>

public fun <T : Any> listOfNotNull(vararg elements: T?): List<T> {
    val result: MutableList<T> = __kk_list_of(null, 0)
    for (element in elements) {
        if (element != null) result.add(element)
    }
    return result
}

public fun <T> List<T>.count(predicate: (T) -> Boolean): Int {
    var count = 0
    var i = 0
    while (i < size) { if (predicate(this[i])) count += 1; i += 1 }
    return count
}

public fun <T> List<T>.any(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (predicate(this[i])) return true; i += 1 }
    return false
}

public fun <T> List<T>.all(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (!predicate(this[i])) return false; i += 1 }
    return true
}

public fun <T> List<T>.none(predicate: (T) -> Boolean): Boolean {
    var i = 0
    while (i < size) { if (predicate(this[i])) return false; i += 1 }
    return true
}

public fun <T> List<T>.sumOf(selector: (T) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < size) { sum += selector(this[i]); i += 1 }
    return sum
}

public fun <T, R : Comparable<R>> List<T>.maxByOrNull(selector: (T) -> R): T? {
    if (length == 0) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (key > bestKey) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}

public fun <T, R : Comparable<R>> List<T>.minByOrNull(selector: (T) -> R): T? {
    if (length == 0) return null
    var bestElem = this[0]
    var bestKey = selector(bestElem)
    var i = 1
    while (i < size) {
        val elem = this[i]
        val key = selector(elem)
        if (key < bestKey) { bestElem = elem; bestKey = key }
        i += 1
    }
    return bestElem
}
"""

    // repeat / reversed / padStart / padEnd are pure Kotlin but not yet in .kt files.
    // encodeToByteArray / decodeToString delegate to C-bridge primitives (__kk_*).
    // The case-conversion functions (lowercase, uppercase, capitalize, replaceFirstChar,
    // locale variants) have been migrated to StringCaseConversion.kt.
    static let kotlinTextSource = ""

    // MIGRATION-SEQ-003: Sequence collection-conversion HOFs
    // toList / toSet / toMutableList use forEach as the iteration primitive
    // (intercepted by CollectionLiteralLoweringPass to kk_sequence_forEach).
    //
    // Terminal HOFs (first, last, single, count, any, all, none, …) are resolved
    // via synthetic stubs (HeaderHelpers+SyntheticSequenceTerminalStubs.swift) to
    // the C-level kk_sequence_* entry points in RuntimeSequence.swift.  They are
    // NOT included here to avoid scope pollution that would break Sema resolution
    // for List / Collection / Set receivers with the same member names.
    static let kotlinSequencesSource = """
package kotlin.sequences

// MIGRATION-SEQ-003

public fun <T> Sequence<T>.toList(): List<T> {
    val result = mutableListOf<T>()
    for (element in this) { result.add(element) }
    return result
}

public fun <T> Sequence<T>.toMutableList(): MutableList<T> {
    val result = mutableListOf<T>()
    for (element in this) { result.add(element) }
    return result
}

public fun <T> Sequence<T>.toSet(): Set<T> {
    val result = mutableSetOf<T>()
    for (element in this) { result.add(element) }
    return result
}

"""

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

    private static func residualBundledStdlibSources() -> [(path: String, contents: Data)] {
        let residualSources: [(path: String, source: String)] = [
            ("__bundled_kotlin_collections_stdlib.kt", Self.kotlinCollectionsSource),
            ("__bundled_kotlin_text_stdlib.kt", Self.kotlinTextSource),
            ("__bundled_kotlin_sequences_stdlib.kt", Self.kotlinSequencesSource),
        ]
        return residualSources.map { (path, source) in
            (path: path, contents: Data(source.utf8))
        }
    }

    /// Collects bundled stdlib `.kt` sources from `resourcePath/Stdlib`, plus
    /// the residual inline sources. Throws `LoadError` when the resource path
    /// is missing, the `Stdlib` directory cannot be enumerated, or a `.kt` file
    /// cannot be read.
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

        bundledSources.append(contentsOf: Self.residualBundledStdlibSources())
        return bundledSources.sorted(by: { $0.path < $1.path })
    }

    private static let _bundledStdlibSources: [(path: String, contents: Data)] =
        (try? Self.collectBundledStdlibSources()) ?? Self.residualBundledStdlibSources()

    /// Returns all bundled stdlib sources as (virtualPath, contents) pairs in a
    /// deterministic order. This matches the sources injected by `LoadSourcesPhase`
    /// and is used to compute the stdlib manifest hash for incremental builds.
    static func bundledStdlibSources() -> [(path: String, contents: Data)] {
        _bundledStdlibSources
    }

    private static let _manifestHash: String = Self.stableFNV1a64Hex(for: _bundledStdlibSources)

    /// Returns a stable hash of the bundled stdlib manifest.
    static func manifestHash() -> String {
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
