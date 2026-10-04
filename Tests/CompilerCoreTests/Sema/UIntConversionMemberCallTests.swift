#if canImport(Testing)
@testable import CompilerCore
import Testing

/// KSP-1532: `UInt.toChar()` does not exist in Kotlin (verified against
/// kotlinc 2.4.20 and the v2.3.10 stdlib source, and by reflecting
/// `UInt::class.members`), so it must stay unresolved rather than being
/// source-backed. The dead `kk_uint_to_char` bridge (Runtime/RuntimeABI/
/// CallLowerer) has been removed; the other 9 UInt numeric conversions
/// remain compiler/runtime-owned residuals via the primitive-specials fast
/// path, not Sema symbols.
@Suite
struct UIntConversionMemberCallTests {
    @Test
    func uintResidualConversionsTypeCheck() throws {
        let ctx = makeContextFromSource("""
        fun probe(u: UInt) {
            val a: Int = u.toInt()
            val b: Double = u.toDouble()
            val c: Long = u.toLong()
        }
        """)

        try runSema(ctx)
        #expect(
            !ctx.diagnostics.hasError,
            "Expected UInt.toInt()/toDouble()/toLong() to type-check, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func uintToCharIsUnresolved() throws {
        let ctx = makeContextFromSource("""
        fun probe(u: UInt) = u.toChar()
        """)

        try runSema(ctx)
        #expect(
            ctx.diagnostics.hasError,
            "Expected UInt.toChar() to be rejected: Kotlin has no such member"
        )
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" },
            "Expected unresolved-member diagnostic KSWIFTK-SEMA-0024, got: \(ctx.diagnostics.diagnostics.map(\.code))"
        )
    }
}
#endif
