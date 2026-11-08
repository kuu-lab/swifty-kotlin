#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-4435: `shuffled(random:)` bound through the synthetic collection
/// fallback without consulting its real `kotlin.random.Random` parameter
/// signature, so `list.shuffled(42)` compiled and reached the runtime
/// bridge with an Int where a Random object was expected (vtable panic).
/// kotlinc rejects these calls at compile time, and these tests pin that
/// parity while keeping the admissible `Random` arguments on the fallback.
@Suite
struct CollectionShuffledRandomArgumentConformanceTests {
    @Test
    func nonRandomArgumentsAreRejected() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val ints = listOf(1, 2, 3)
            val strings = listOf("a", "b")
            println(ints.shuffled(42))
            println(ints.shuffled("x"))
            println(ints.shuffled(1.5))
            println(ints.shuffled(null))
            println(strings.shuffled(42))
            println(sequenceOf(1, 2, 3).shuffled(42))
            println(mutableListOf(1, 2, 3).shuffled(42))
            println(setOf(1, 2, 3).shuffled(42))
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 8, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func randomArgumentsStillResolve() throws {
        let ctx = makeContextFromSource("""
        import kotlin.random.Random

        fun List<Int>.shuffled(seed: Int): String = "user-$seed"

        fun main() {
            val ints = listOf(1, 2, 3)
            println(ints.shuffled().size)
            println(ints.shuffled(Random(42)).size)
            println(ints.shuffled(Random.Default).size)
            println(ints.shuffled(random = Random(7)).size)
            println(sequenceOf(1, 2, 3).shuffled(Random(3)).toList().size)
            println(setOf(1, 2, 3).shuffled(Random(5)).size)
            println(mutableListOf(1, 2, 3).shuffled(Random(9)).size)
            println((1..10).shuffled().size)
            println(ints.shuffled(42))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
