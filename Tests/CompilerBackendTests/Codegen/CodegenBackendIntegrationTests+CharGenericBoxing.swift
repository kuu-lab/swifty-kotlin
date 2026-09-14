#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// A `Char` stored in a `MutableList<Char>` via `.add()` is inserted through
/// `runtimeMutableListInsertedValue` (`Sources/Runtime/RuntimeCollections.swift`),
/// which unboxes a genuine `RuntimeCharBox` pointer into an optimized
/// `RuntimeValue(charScalar:)` representation (`tag = charTag`, `payload0` =
/// the raw scalar) rather than keeping the boxed pointer around.
///
/// `RuntimeValue.legacyRawValue` (`Sources/Runtime/RuntimeTypes.swift`) is the
/// single place that representation gets handed back out as a generic `Int`
/// handle — used by `List<R>.get()`, iteration, `toCollection`, and every
/// other generic read path. It already re-materializes a real
/// `RuntimeStringBox` pointer for `stringTag`, but used to fall through to
/// `payload0` unchanged for `charTag`, returning the bare unboxed scalar.
/// That raw scalar is indistinguishable from a plain `Int` once it crosses an
/// erased `T`/`R`/`Any` boundary (e.g. flowing into another generic
/// function's `MutableList<R>.add(element: R)`), so the receiving collection
/// stored — and later printed — it as a number instead of a character.
///
/// Fixed by giving `charTag` its own `legacyRawValue` case that
/// re-materializes a `RuntimeCharBox`, mirroring the existing `stringTag`
/// case. Expected outputs cross-checked against kotlinc via
/// `diff_kotlinc.sh`.
@Suite
struct CodegenBackendCharGenericBoxingTests {
    /// The originally reported repro: `flatMap`'s generic destination list
    /// receives each inner list's `Char` elements through exactly this path.
    @Test
    func flatMapOverStringToListPreservesCharElements() throws {
        let source = """
        fun main() {
            val r: List<Char> = listOf("a", "bb").flatMap { it.toList() }
            println(r)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "FlatMapCharBoxingRuntime",
            expected: "[a, b, b]\n"
        )
    }

    /// Isolates the underlying mechanism independent of `flatMap`'s own
    /// implementation: a user-defined generic function that iterates a
    /// `List<R>` and re-inserts each element into a fresh `MutableList<R>`.
    /// Only a list whose elements were inserted via `.add()` (not the
    /// `listOf(...)` vararg factory, which boxes explicitly at every call
    /// site) exercises the buggy `charTag` path before the fix.
    @Test
    func genericPassThroughPreservesCharElementsRegardlessOfSourceConstruction() throws {
        let source = """
        fun <R> passThroughList(list: List<R>): List<R> {
            val result = mutableListOf<R>()
            for (item in list) {
                result.add(item)
            }
            return result
        }

        fun main() {
            val viaMutable: List<Char> = mutableListOf<Char>().also { it.add('x'); it.add('y') }
            println(passThroughList(viaMutable))
            val viaFactory: List<Char> = listOf('a', 'b')
            println(passThroughList(viaFactory))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "GenericPassThroughCharBoxingRuntime",
            expected: """
            [x, y]
            [a, b]

            """
        )
    }

    /// The same generic round trip through a different erased container
    /// (`MutableSet<R>`) — pins that the `legacyRawValue` fix is not
    /// `MutableList`-specific.
    @Test
    func genericPassThroughToSetPreservesCharElements() throws {
        let source = """
        fun <R> passThroughToSet(list: List<R>): Set<R> {
            val result = mutableSetOf<R>()
            for (item in list) {
                result.add(item)
            }
            return result
        }

        fun main() {
            val viaMutable: List<Char> = mutableListOf<Char>().also { it.add('p'); it.add('q') }
            println(passThroughToSet(viaMutable))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "GenericPassThroughSetCharBoxingRuntime",
            expected: "[p, q]\n"
        )
    }
}
#endif
