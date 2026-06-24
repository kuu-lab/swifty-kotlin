@testable import CompilerCore
import Testing

@Suite
struct SystemMeasureTimeMillisFunctionTests {
    @Test
    func testMeasureTimeMillisFunctionResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlin.system.measureTimeMillis

        fun timeIt(): Long {
            return measureTimeMillis {
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
