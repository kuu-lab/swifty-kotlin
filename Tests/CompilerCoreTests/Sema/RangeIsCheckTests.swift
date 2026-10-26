@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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
            ints is ClosedRange<*>
            ints is OpenEndRange<*>
            ints is Iterable<*>
            longs is LongRange
            longs is LongProgression
            chars is CharRange
            chars is CharProgression
            val doubles = 1.0..5.0
            doubles is ClosedFloatingPointRange<*>
            doubles is ClosedRange<*>
            doubles is Iterable<*>
        }
        fun unrelatedTargets(value: Int) {
            value is IntRange
            val ints = 1..5
            ints is LongRange
            ints is List<*>
        }
        """)

        try runSema(ctx)

        let alwaysFalseDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-0415"
        }
        #expect(alwaysFalseDiagnostics.count == 4, "Expected incompatible final and mismatched-range checks to be rejected: \(alwaysFalseDiagnostics)")
    }
}
