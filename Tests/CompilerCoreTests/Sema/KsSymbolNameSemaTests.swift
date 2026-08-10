@testable import CompilerCore
import Testing

@Suite
struct KsSymbolNameSemaTests {

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    @Test
    func testKsSymbolNameSema() throws {
        let sources: [String] = [
            // interfaceBodylessFunctionDoesNotRequireBody
            """
            package sample0

                    interface Shape {
                        fun area(): Int
                    }

            """,
            // userKsSymbolNameAnnotationIsRejected
            """
            package sample1

                    import kotlin.internal.KsSymbolName

                    @KsSymbolName("kk_user_bridge")
                    fun userBridge(value: Int): Int = value

            """,
            // userExternalFunctionIsRejectedWithoutBodylessDiagnostic
            """
            package sample2

                    external fun userBridge(value: Int): Int

            """,
            // userKsSymbolNameExternalFunctionReportsReservedDiagnostics
            """
            package sample3

                    import kotlin.internal.KsSymbolName

                    @KsSymbolName(name = "kk_user_bridge")
                    external fun userBridge(value: Int): Int

            """,
            // nonExternalBodylessFunctionStillRequiresBody
            """
            package sample4

                    fun missingBody(): Int

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // === interfaceBodylessFunctionDoesNotRequireBody ===
            do {
                let sample0Diagnostics = diagnosticsForPath(paths[0], in: ctx)
                assertNoDiagnostic("KSWIFTK-SEMA-0009", in: sample0Diagnostics)
            }

            // === userKsSymbolNameAnnotationIsRejected ===
            do {
                let sample1Diagnostics = diagnosticsForPath(paths[1], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0007", in: sample1Diagnostics)
            }

            // === userExternalFunctionIsRejectedWithoutBodylessDiagnostic ===
            do {
                let sample2Diagnostics = diagnosticsForPath(paths[2], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0008", in: sample2Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0009", in: sample2Diagnostics)
            }

            // === userKsSymbolNameExternalFunctionReportsReservedDiagnostics ===
            do {
                let sample3Diagnostics = diagnosticsForPath(paths[3], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0007", in: sample3Diagnostics)
                assertHasDiagnostic("KSWIFTK-SEMA-0008", in: sample3Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0009", in: sample3Diagnostics)
            }

            // === nonExternalBodylessFunctionStillRequiresBody ===
            do {
                let sample4Diagnostics = diagnosticsForPath(paths[4], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0009", in: sample4Diagnostics)
            }
        }
    }
}
