#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// A `when` used as a property initializer parses its entries outside a
/// block, so a branch body's lambda is consumed flat. A `;` inside that
/// lambda (`0 -> run { a(); b }`) must stay inside the lambda instead of
/// ending the entry and splitting the rest into a bogus new entry.
@Suite
struct WhenInitializerLambdaSemicolonTests {
    @Test
    func semicolonInsideBranchLambdaOfPropertyInitializerWhen() throws {
        let parsed = parse("""
        fun main() {
            var calls = ""
            val r = when (1) {
                0 -> run { calls += "x"; 1 }
                1 -> run { calls += "y"; 2 }
                else -> 3
            }
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .whenEntry } == 3)
    }

    @Test
    func semicolonInsideBranchLambdaOfSubjectlessPropertyInitializerWhen() throws {
        let parsed = parse("""
        fun main() {
            var calls = ""
            val r = when {
                calls.isEmpty() -> run { calls = "x"; 1 }
                else -> 3
            }
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .whenEntry } == 2)
    }
}
#endif
