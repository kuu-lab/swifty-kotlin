@testable import CompilerCore
import Testing

@Suite
struct SystemMeasureTimeMicrosFunctionTests {
    @Test
    func testMeasureTimeMicrosFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.measureTimeMicros

        fun timeIt(): Long {
            return measureTimeMicros {
                var sum = 0
                for (i in 1..100) {
                    sum += i
                }
            }
        }
        """)
        try runSema(ctx)
        #expect(!(ctx.diagnostics.hasError), "resolve: \(ctx.diagnostics.diagnostics)")
    }
}
