#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
