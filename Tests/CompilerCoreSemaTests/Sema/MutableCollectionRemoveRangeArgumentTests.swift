#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4328: `ints.remove(2..4)` and `doubles.remove(1.5..2.5)` were accepted
/// in native mode while kotlinc rejects them. The member
/// `MutableCollection.remove(element: E)` correctly rejected the range
/// argument, but the bundled stdlib's
/// `MutableCollection<out T>.remove(element: T)` extension was missing the
/// upstream `@OnlyInputTypes` annotation, so its type parameter was inferred
/// as `Any` and accepted any argument type.
@Suite
struct MutableCollectionRemoveRangeArgumentTests {
    @Test
    func rangeArgumentsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val ints = mutableListOf(1, 2, 3, 4, 5)
            val doubles = mutableListOf(1.0, 2.0, 3.0)
            val intRangeVar = 2..4
            println(ints.remove(2..4))
            println(doubles.remove(1.5..2.5))
            println(ints.remove(intRangeVar))
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 3, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func elementArgumentsStillResolve() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val ints = mutableListOf(1, 2, 3, 4, 5)
            val set = mutableSetOf(1, 2, 3)
            val rangeElements = mutableListOf(1..3, 4..6)
            println(ints.remove(2))
            println(set.remove(2))
            println(rangeElements.remove(1..3))
            println(ints.removeAll(listOf(2, 3)))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
