#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// A subject-less `when` branch condition split across newlines after an
/// infix operator must stay a single condition — `a ||\n b` continues the
/// expression rather than starting a new entry.
@Suite
struct WhenConditionMultilineOperatorTests {
    @Test
    func disjunctionChainAcrossNewlinesParsesAsOneCondition() throws {
        let parsed = parse("""
        fun choose(flag: Int): Int = when {
            flag == 1 ||
                flag == 2 ||
                flag == 3 ||
                flag == 4 -> 10
            else -> 0
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .whenEntry } == 2)
    }

    @Test
    func isTypeConditionSurvivesNewlineAfterTypeArgumentList() throws {
        let parsed = parse("""
        fun pick(x: Any): Int = when (x) {
            is List<Int>
                -> 1
            else -> 0
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .whenEntry } == 2)
    }
}
#endif
