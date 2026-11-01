@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

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

    // KUU-4039: kotlin.ranges.step exists only on the integral ranges and
    // progressions; kotlinc reports "unresolved reference 'step'" for
    // floating-point receivers. The infix `step` operator used to bypass
    // member resolution, type as IntProgression, and lower `__kk_op_step`
    // onto a floating-point range box, panicking at runtime.
    @Test(arguments: ["1.0..3.0", "1f..3f", "1.0..<3.0", "1f..<3f"])
    func rejectsInfixStepOnFloatingPointRanges(range: String) throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun test() {
            val stepped = \(range) step 2
            val range = \(range)
            val steppedVar = range step 2
            for (x in \(range) step 2) {
                println(x)
            }
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 3, "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0024" }, "\(errors)")
    }

    @Test
    func keepsInfixStepOnIntegralRanges() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        fun test() {
            println((1..10 step 2).toList())
            println((10 downTo 1 step 3).toList())
            println((1L..10L step 3L).toList())
            println(('a'..'z' step 2).toList())
            println((1u..10u step 2).toList())
            println((1uL..10uL step 2).toList())
        }
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
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

    @Test
    func keepsUserRangeToExtensionForDifferentRightOperand() throws {
        TestStdlibCache.shared.prepare()
        let ctx = makeContextFromSource("""
        operator fun Double.rangeTo(end: String): String = end
        fun test(): String = 1.0.."custom"
        """, allowDefaultStdlibLibrary: true)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
