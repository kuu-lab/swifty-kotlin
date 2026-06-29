@testable import CompilerCore
import Testing

@Suite
struct SystemMeasureNanoTimeFunctionTests {
    @Test
    func testMeasureNanoTimeFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.measureNanoTime

        fun timeIt(): Long {
            return measureNanoTime {
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
