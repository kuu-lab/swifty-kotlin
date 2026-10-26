#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct EmptyControlFlowConditionTests {
    @Test
    func rejectsEmptyControlFlowConditionsWithoutCascading() throws {
        let source = """
        val r = if () 1 else 2
        val choice = when () { else -> 1 }
        fun main() {
            if () println(1)
            if () { println(1) } else { println(2) }
            while () println(1)
            do { println(1) } while ()
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.map(\.code) == Array(repeating: "KSWIFTK-PARSE-0001", count: 6))
        #expect(errors.allSatisfy { $0.message == "Expected expression." })
    }

    @Test
    func keepsValidControlFlowConditions() throws {
        let source = """
        val result = when { else -> 1 }
        fun main() {
            if (true) println(1)
            while (false) println(1)
            do { println(1) } while (false)
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
