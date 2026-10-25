@testable import CompilerCore
import Testing

/// Regression coverage for KUU-3232 / JetBrains `unsignedTypes/kt47716.kt`:
/// a bare class-name expression (`ULong`) denotes the companion object, so a
/// compound expression that yields it (try/if/when/elvis/lambda result) must
/// keep the companion value type for postfix member lookup.
@Suite
struct ClassNameCompanionResultTests {
    @Test
    func tryFinallyResultResolvesCompanionMember() throws {
        let ctx = makeContextFromSource("""
        fun box(): String {
            val r = try { ULong } finally { Unit }.MAX_VALUE
            return if (r == ULong.MAX_VALUE) "OK" else "FAIL"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func tryFinallyLocalAliasResolvesCompanionMember() throws {
        let ctx = makeContextFromSource("""
        fun box(): String {
            val c = try { ULong } finally { Unit }
            return if (c.MAX_VALUE == ULong.MAX_VALUE) "OK" else "FAIL"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func kt47716PublicShapeResolvesCompanionMember() throws {
        let ctx = makeContextFromSource("""
        fun box(): String {
            val r =
                try {
                    ULong
                } finally {
                    UInt.MAX_VALUE
                }.MAX_VALUE
            return if (r == ULong.MAX_VALUE) "OK" else "FAIL"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func compoundExpressionResultsResolveCompanionMember() throws {
        let ctx = makeContextFromSource("""
        fun box(): String {
            val fromIf = if (true) ULong else ULong
            val fromWhen = when (true) { true -> ULong; else -> ULong }
            val fromRun = run { ULong }
            val fromLambda = { ULong }()
            val fromElvis = null ?: ULong
            val fromTryCatch = try { ULong } catch (e: Exception) { ULong }
            val fromLabeledReturn = run { return@run ULong }
            val results = listOf(
                fromIf.MAX_VALUE,
                fromWhen.MAX_VALUE,
                fromRun.MAX_VALUE,
                fromLambda.MAX_VALUE,
                fromElvis.MAX_VALUE,
                fromTryCatch.MAX_VALUE,
                fromLabeledReturn.MAX_VALUE
            )
            return if (results.all { it == ULong.MAX_VALUE }) "OK" else "FAIL"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func missingCompanionMemberStillRejected() throws {
        let ctx = makeContextFromSource("""
        fun box(): String {
            val c = try { ULong } finally { Unit }
            return c.NOT_A_MEMBER
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0024", in: ctx)
    }
}
