#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativeCInteropBetaInteropApiTests {

    private func diagnosticsForPath(_ path: String, in ctx: CompilationContext) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    @Test
    func testBetaInteropApiSema() throws {
        let sources: [String] = [
            """
            package sample0
            fun noop() {}
            """,
            """
            package sample1
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
            """,
            """
            package sample2
            import kotlinx.cinterop.BetaInteropApi

            @BetaInteropApi
            fun betaFunction() {}

            fun probe() {
                betaFunction()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let betaInteropApiSymbol = try #require(
                sema.symbols.lookup(fqName: ["kotlinx", "cinterop", "BetaInteropApi"].map { interner.intern($0) }),
                "kotlinx.cinterop.BetaInteropApi must be registered"
            )

            // testBetaInteropApiAnnotationIsRegistered
            do {
                #expect(sema.symbols.symbol(betaInteropApiSymbol)?.kind == .annotationClass)
            }

            // testBetaInteropApiCarriesOfficialTargets
            do {
                let target = try #require(
                    sema.symbols.annotations(for: betaInteropApiSymbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
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

            // testBetaInteropApiCarriesRequiresOptInWarning
            do {
                let requiresOptIn = try #require(
                    sema.symbols.annotations(for: betaInteropApiSymbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
                    "BetaInteropApi must carry @RequiresOptIn"
                )
                #expect(
                    requiresOptIn.arguments.contains("level=RequiresOptIn.Level.WARNING"),
                    "BetaInteropApi must be a warning-level opt-in marker; got \(requiresOptIn.arguments)"
                )
            }

            // testBetaInteropApiIsAcceptedOnOfficialTargets
            do {
                let sample1Path = paths[1]
                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)
                #expect(sample1Diagnostics.isEmpty, "Expected BetaInteropApi on official targets to compile cleanly, got: \(sample1Diagnostics)")
            }

            // testUsingBetaInteropApiWithoutOptInProducesWarningDiagnostic
            do {
                let sample2Path = paths[2]
                let optInWarnings = diagnosticsForPath(sample2Path, in: ctx).filter {
                    $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
                }
                #expect(!(optInWarnings.isEmpty), "Expected warning-level opt-in diagnostic for BetaInteropApi usage")
            }
        }
    }
}
#endif
