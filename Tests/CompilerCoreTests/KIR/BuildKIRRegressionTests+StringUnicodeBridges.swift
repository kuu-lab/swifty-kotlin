#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension BuildKIRRegressionTests {
    /// KSP-417 keeps normalization, codePointCount, and random as runtime bridges,
    /// but demotes their symbols to the private `__kk_` tier.
    @Test func testUnicodeNormalizationAndRandomLowerToPrivateRuntimeBridges() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val s = "e\\u0301abc"
            val nfc = s.normalize(NormalizationForms.NFC)
            val nfd = s.normalize(NormalizationForms.NFD)
            val nfkc = s.normalize(NormalizationForms.NFKC)
            val nfkd = s.normalize(NormalizationForms.NFKD)
            val stable = nfc.isNormalized(NormalizationForms.NFC)
            val total = s.codePointCount()
            val from = s.codePointCount(1)
            val range = s.codePointCount(0, 2)
            val any = s.random()
            val seeded = s.random(Random(42))
            println("$nfd $nfkc $nfkd $stable $total $from $range $any $seeded")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = Set(extractCallees(from: body, interner: ctx.interner))

            let expected = [
                "__kk_normalization_form_nfc",
                "__kk_normalization_form_nfd",
                "__kk_normalization_form_nfkc",
                "__kk_normalization_form_nfkd",
                "__kk_string_normalize_flat",
                "__kk_string_isNormalized_flat",
                "__kk_string_codePointCount",
                "__kk_string_codePointCount_from",
                "__kk_string_codePointCount_range",
                "__kk_string_random",
                "__kk_string_random_random",
            ]
            for callee in expected {
                #expect(callees.contains(callee), "\(callee) should be the emitted runtime callee")
            }

            let demotedRuntimeCallees = Set(expected.map { String($0.dropFirst(2)) })
            #expect(
                callees.isDisjoint(with: demotedRuntimeCallees),
                "Public kk_ names should be gone: \(callees.intersection(demotedRuntimeCallees))"
            )
        }
    }
}
#endif
