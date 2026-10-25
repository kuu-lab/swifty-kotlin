#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct SpeculativeStatementProbeDiagnosticsTests {
    // KUU-3161: a statement-group assignment probe parsed `do x -= 1` as a
    // compound-assign LHS and leaked "Expected 'while' after 'do' block" even
    // though the trailing `while (…)` was present.
    @Test
    func unbracedDoWhileWithCompoundAssignBody() throws {
        let source = """
        fun unbracedBody(start: Int): Int {
            var value = start
            do value -= 1 while (value > 0)
            return value
        }

        fun main() {
            val result = unbracedBody(3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }

    // KUU-3162: a `get`/`set` call inside an object-literal property
    // initializer matched the accessor heuristic, and the speculative
    // truncated-prefix parse leaked "Expected expression"/branch diagnostics.
    @Test
    func objectLiteralInitializerWithGetSetCallsAndIfElse() throws {
        let source = """
        fun get(x: Int): Int = x * 10
        fun set(x: Int): Int = x + 100
        fun get(block: () -> Int): Int = block()
        infix fun Int.choose(other: Int): Int = this + other

        fun main() {
            val plain = object {
                val comparison = 2 > get() { 1 }
                val conditional = if (true) 1 else if (false) get() { 2 } else 3
                val infix = 1 choose get() { 2 }
                var raw = 3
                var value: Int
                    get() = get(raw)
                    set(v) { raw = set(v) }
            }
            val a = plain.comparison
            val b = plain.conditional
            val c = plain.infix
        }
        """

        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }
}
#endif
