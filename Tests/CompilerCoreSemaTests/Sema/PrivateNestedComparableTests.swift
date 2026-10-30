@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct PrivateNestedComparableTests {
    @Test
    func privateNestedComparableSequenceCanBeSortedAndIndexed() throws {
        let ctx = makeContextFromSource("""
        class Solver {
            private class Hand(val bid: Int) : Comparable<Hand> {
                override fun compareTo(other: Hand): Int = bid - other.bid
            }
            fun run(): Int = sequenceOf(Hand(3), Hand(1)).sorted().mapIndexed { index,hand -> hand.bid * (index+1) }.sum()
        }
        fun main() { println(Solver().run())}
        """)

        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected error codes: \(errors.map(\.code))")
    }
}
