@testable import CompilerCore
import Testing

@Suite
struct LineSeparatedLoopLabelBindingTests {
    @Test
    func lineSeparatedLabelsResolveForBreakAndContinue() throws {
        let context = makeContextFromSource("""
        fun test() {
            var n = 0
            outer@
            for (i in 0 until 3) {
                for (j in 0 until 3) {
                    if (i + j > 1) break@outer
                    n++
                }
            }

            whileLoop@
            while (n < 2) {
                n++
                continue@whileLoop
            }

            doLoop@
            do {
                n++
                break@doLoop
            } while (n < 10)
        }
        """)

        try runSema(context)

        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")
    }
}
