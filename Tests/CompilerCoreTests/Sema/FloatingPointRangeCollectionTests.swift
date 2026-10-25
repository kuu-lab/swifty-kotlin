@testable import CompilerCore
import Testing
import TestStdlibCache

@Suite
struct FloatingPointRangeCollectionTests {
    @Test(arguments: ["1.0..3.0", "1f..3f", "1.0..<3.0", "1f..<3f"])
    func rejectsCollectionOperationsOnFloatingPointRanges(range: String) throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun test() {
            (\(range)).toList()
            val range = \(range)
            range.toList()
            range.map { 1 }
            range.step(1)
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 4, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" }, "\(errors)")
    }

    @Test
    func preservesFloatingPointRangeMembersAndUserExtensions() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        import kotlin.ranges.ClosedFloatingPointRange
        fun ClosedFloatingPointRange<Double>.toList(): List<Double> = listOf(start, endInclusive)
        fun test() {
            val range = 1.0..3.0
            val start: Double = range.start
            val end: Double = range.endInclusive
            val contains: Boolean = range.contains(2.0)
            val empty: Boolean = range.isEmpty()
            val member: Boolean = 2.0 in range
            val values: List<Double> = range.toList()
            val direct: List<Double> = (1.0..3.0).toList()
            val ints: List<Int> = (1..3).toList()
            val longs: List<Long> = (1L..3L).toList()
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
