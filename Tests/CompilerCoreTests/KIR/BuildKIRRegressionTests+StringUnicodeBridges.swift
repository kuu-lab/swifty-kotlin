#if canImport(Testing)
@testable import CompilerCore
import Testing

extension BuildKIRRegressionTests {
    /// KSP-417 kept normalization and codePointCount as runtime bridges,
    /// demoted to the private `__kk_` tier, and the old synthetic stubs had
    /// no Kotlin body of their own — a call to them inlined the runtime
    /// callee directly into the caller's KIR. KSP-717 moved normalize /
    /// isNormalized / codePointCount to real bundled Kotlin functions
    /// (StringNormalize.kt / StringBasics.kt) compiled once into the shared
    /// stdlib artifact: `main` now resolves them as ordinary function calls
    /// by their own name, and their internal `__kk_*` bridge calls live in
    /// those functions' own (separately compiled) KIR bodies, invisible to
    /// `main`'s. The bridges' `__kk_` link names are covered at the Sema
    /// level by StringSyntheticMemberLinkTests; this only needs to confirm
    /// `main` no longer inlines a raw runtime callee for these calls.
    /// NormalizationForms.NFC/NFD/NFKC/NFKD are plain Kotlin property
    /// initializers now, so their runtime bridges are gone entirely (not just
    /// demoted) and must never appear as a callee anywhere.
    @Test func testUnicodeNormalizationAndCodePointCountResolveToBundledKotlinFunctions() throws {
        let source = """
        fun main() {
            val s = "e\\u0301abc"
            val nfc = s.normalize(NormalizationForms.NFC)
            val stable = nfc.isNormalized(NormalizationForms.NFC)
            val total = s.codePointCount()
            val from = s.codePointCount(1)
            val range = s.codePointCount(0, 2)
            println("$stable $total $from $range")
        }
        """

        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
        let callees = Set(extractCallees(from: body, interner: ctx.interner))

        for expected in ["normalize", "isNormalized", "codePointCount"] {
            #expect(callees.contains(expected), "main should call the bundled Kotlin function \(expected) by name")
        }
        #expect(
            callees.isDisjoint(with: [
                "__kk_string_normalize_flat",
                "__kk_string_isNormalized_flat",
                "__kk_string_codePointCount",
                "__kk_string_codePointCount_from",
                "__kk_string_codePointCount_range",
                "__kk_normalization_form_nfc",
                "__kk_normalization_form_nfd",
                "__kk_normalization_form_nfkc",
                "__kk_normalization_form_nfkd",
            ]),
            "main should not inline a direct runtime-bridge callee for these anymore; got \(callees)"
        )
    }
}
#endif
