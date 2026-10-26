#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

extension LoweringPassRegressionTests {
    @Test
    func testCharSequenceIfEmptyUsesLengthOnlyRuntimeFallback() throws {
        let source = """
        fun choose(value: CharSequence): CharSequence = value.ifEmpty { "fallback" }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "CharSequenceIfEmptyRuntimeFallback",
                emit: .kirDump,
                allowDefaultStdlibLibrary: false
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "choose", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)

            #expect(
                callees.contains("kk_charsequence_ifEmpty"),
                "CharSequence.ifEmpty should use the runtime fallback; callees: \(callees)"
            )
        }
    }
}
#endif
