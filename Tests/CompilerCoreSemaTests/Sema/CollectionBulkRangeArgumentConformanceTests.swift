#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4318: `containsAll`/`addAll`/`removeAll`/`retainAll` used to bind
/// through the synthetic collection fallback without checking the argument
/// against the real `Collection`-parameter signatures, and `add`/`remove`/
/// `contains` bound the same way without an element-type check. Range
/// expressions keep scalar or nominal range types that are not `Collection`
/// (`IntRange` is only `Iterable`; `ClosedFloatingPointRange` is neither), so
/// the calls compiled and crashed with `ClassCastException` at runtime.
/// kotlinc rejects them at compile time, and these tests pin that parity.
@Suite
struct CollectionBulkRangeArgumentConformanceTests {
    @Test
    func rangeAndNonCollectionArgumentsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val ints = mutableListOf(1, 2, 3, 4, 5)
            val doubles = mutableListOf(1.0, 2.0, 3.0)
            val floats = mutableListOf(1.0f, 2.0f, 3.0f)
            val set = mutableSetOf(1, 2, 3)
            val intRangeVar = 2..4
            println(ints.containsAll(2..4))
            println(ints.containsAll(intRangeVar))
            println(doubles.containsAll(1.5..2.5))
            println(floats.containsAll(1.5f..2.5f))
            println(set.containsAll(2..4))
            println(ints.containsAll(42))
            println(ints.containsAll("x"))
            println(ints.containsAll(listOf("x")))
            println(doubles.removeAll(1.5..2.5))
            println(floats.addAll(1.5f..2.5f))
            println(doubles.retainAll(1.5..2.5))
            println(ints.removeAll("x"))
            println(ints.addAll(42))
            println(ints.retainAll(1.5..2.5))
            println(ints.contains(2..4))
            println(ints.add(2..4))
            println(ints.contains("x"))
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 17, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func iterableRangesAndCollectionArgumentsStillResolve() throws {
        let ctx = makeContextFromSource("""
        fun takesIterable(values: Iterable<Int>): Int = values.count()
        fun main() {
            val ints = mutableListOf(1, 2, 3, 4, 5)
            val set = mutableSetOf(1, 2, 3)
            val intRangeVar = 2..4
            val rangeElements = mutableListOf(1..3, 4..6)
            val map = mutableMapOf(1 to "a", 2 to "b")
            println(ints.addAll(2..4))
            println(ints.removeAll(2..4))
            println(ints.retainAll(2..4))
            println(ints.addAll(intRangeVar))
            println(set.removeAll(2..4))
            println(set.addAll(5..6))
            println(set.retainAll(1..2))
            println(takesIterable(1..10))
            println(ints.containsAll(listOf(1, 2)))
            println(ints.containsAll(setOf(1, 2)))
            println(ints.containsAll(elements = listOf(1, 2)))
            println(ints.removeAll(listOf(2, 3)))
            println(ints.addAll(mutableListOf(6)))
            println(ints.retainAll(setOf(1)))
            println(ints.remove(2))
            println(ints.contains(3))
            println(ints.add(6))
            println(rangeElements.remove(1..3))
            println(rangeElements.contains(4..6))
            println(map.remove(1))
            println(map.containsKey(2))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
