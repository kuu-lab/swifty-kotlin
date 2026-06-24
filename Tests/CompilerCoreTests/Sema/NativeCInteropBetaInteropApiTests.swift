#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropBetaInteropApiTests {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Expected BetaInteropApi surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)")
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    private func betaInteropApiSymbol(sema: SemaModule, interner: StringInterner) throws -> SymbolID {
        try #require(sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "BetaInteropApi"].map { interner.intern($0) }), "kotlinx.cinterop.BetaInteropApi must be registered")
    }

    @Test func testBetaInteropApiAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let symbol = try betaInteropApiSymbol(sema: sema, interner: interner)

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
    }

    @Test func testBetaInteropApiCarriesOfficialTargets() throws {
        let (sema, interner) = try makeSema()
        let symbol = try betaInteropApiSymbol(sema: sema, interner: interner)
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "BetaInteropApi must carry @Target metadata"
        )
        let expectedTargets = [
            "AnnotationTarget.TYPEALIAS",
            "AnnotationTarget.FUNCTION",
            "AnnotationTarget.PROPERTY",
            "AnnotationTarget.ANNOTATION_CLASS",
            "AnnotationTarget.CLASS",
        ]

        #expect(Set(target.arguments) == Set(expectedTargets))
    }

    @Test func testBetaInteropApiCarriesRequiresOptInWarning() throws {
        let (sema, interner) = try makeSema()
        let symbol = try betaInteropApiSymbol(sema: sema, interner: interner)
        let requiresOptIn = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "BetaInteropApi must carry @RequiresOptIn"
        )

        #expect(
            requiresOptIn.arguments.contains("level=RequiresOptIn.Level.WARNING"),
            "BetaInteropApi must be a warning-level opt-in marker; got \(requiresOptIn.arguments)"
        )
    }

    @Test func testBetaInteropApiIsAcceptedOnOfficialTargets() throws {
        _ = try makeSema(source: """
        import kotlinx.cinterop.BetaInteropApi

        @BetaInteropApi
        class BetaClass

        @BetaInteropApi
        annotation class BetaMarker

        @BetaInteropApi
        fun betaFunction() {}

        @BetaInteropApi
        val betaProperty: Int = 1

        @BetaInteropApi
        typealias BetaAlias = String
        """)
    }

    @Test func testUsingBetaInteropApiWithoutOptInProducesWarningDiagnostic() {
        let source = """
        import kotlinx.cinterop.BetaInteropApi

        @BetaInteropApi
        fun betaFunction() {}

        fun probe() {
            betaFunction()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInWarnings = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
        }

        #expect(!(optInWarnings.isEmpty), "Expected warning-level opt-in diagnostic for BetaInteropApi usage")
    }
}
#endif
