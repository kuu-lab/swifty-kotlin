@testable import CompilerCore
import Testing

@Suite
struct RangeIsCheckTests {
    @Test func rangeMarkersAvoidFalseAlwaysFalseDiagnostics() throws {
        let ctx = makeContextFromSource("""
        fun ranges() {
            val ints = 1..5
            val longs = 1L..5L
            val chars = 'a'..'z'
            ints is IntRange
            ints is IntProgression
            longs is LongRange
            longs is LongProgression
            chars is CharRange
            chars is CharProgression
        }
        fun unrelatedTargets(value: Int) {
            value is IntRange
            val ints = 1..5
            ints is LongRange
        }
        """)

        try runSema(ctx)

        let alwaysFalseDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0415"
        }
        #expect(alwaysFalseDiagnostics.count == 2, "Expected only the scalar and mismatched-range checks to be rejected: \(alwaysFalseDiagnostics)")
    }
}
