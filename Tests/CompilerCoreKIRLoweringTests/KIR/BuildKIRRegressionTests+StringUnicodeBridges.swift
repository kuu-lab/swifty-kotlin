#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
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
            try expectSourceBackedCalls(named: ctx.interner.intern(expected), in: body, context: ctx)
        }
        try expectResolvedKIRCallTargets(in: body, context: ctx)
        #expect(
            callees.isDisjoint(with: [
                runtimeCallee(.stringNormalizeFlat),
                runtimeCallee(.stringIsNormalizedFlat),
                runtimeCallee(.stringCodePointCount),
                runtimeCallee(.stringCodePointCountFrom),
                runtimeCallee(.stringCodePointCountRange),
            ]),
            "main should not inline a direct runtime-bridge callee for these anymore; got \(callees)"
        )
    }
}
#endif
