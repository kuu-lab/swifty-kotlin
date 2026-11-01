#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// A `when` used as a declaration tail (property initializer or function
/// body expression) parses its entries outside a block, so a branch body's
/// lambda is consumed flat. A `;` inside that lambda (`0 -> run { a(); b }`)
/// must stay inside the lambda instead of ending the entry and splitting the
/// rest into a bogus new entry (KUU-4089).
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

    /// KUU-4089: subjectless `when` as a function body expression. The
    /// lambda's `;` must not end the entry and its `}` must not be mistaken
    /// for the when body's `}`.
    @Test
    func semicolonInsideBranchLambdaOfFunctionBodyWhen() throws {
        let parsed = parse("""
        fun g(b: () -> Unit) {}
        fun h(x: Int) {}
        fun f() = when {
            true -> g { h(1); h(2) }
            else -> {}
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .whenEntry } == 2)
    }

    /// KUU-4089: `when (x)` as a function body expression where the `else`
    /// branch body is itself a `;`-containing trailing lambda.
    @Test
    func semicolonInsideBranchAndElseLambdasOfFunctionBodyWhen() throws {
        let parsed = parse("""
        fun g(b: () -> Unit) {}
        fun h(x: Int) {}
        fun f(x: Int) = when (x) {
            1 -> g { h(1); h(2) }
            else -> g { h(3); h(4) }
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .whenEntry } == 2)
    }

    /// KUU-4089: a `when` statement inside a block takes the `inBlock` path,
    /// where the branch lambda is parsed as a block node instead of flat
    /// tokens; the `;` must still stay inside the lambda.
    @Test
    func semicolonInsideBranchLambdaOfBlockStatementWhen() throws {
        let parsed = parse("""
        fun g(b: () -> Unit) {}
        fun h(x: Int) {}
        fun f() {
            when {
                true -> g { h(1); h(2) }
                else -> g { h(3); h(4) }
            }
        }
        """)
        #expect(parsed.diagnostics.diagnostics.isEmpty)
        #expect(parsed.arena.nodes.count { $0.kind == .whenEntry } == 2)
    }
}
#endif
