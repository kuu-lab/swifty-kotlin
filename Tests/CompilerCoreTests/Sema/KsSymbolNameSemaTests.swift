@testable import CompilerCore
import Testing

@Suite
struct KsSymbolNameSemaTests {

    // MARK: - Per-source diagnostic helpers

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
            // bodylessKsSymbolNameInterfaceFunctionIsNotAbstract
            """
            package sample5

                    import kotlin.internal.KsSymbolName

                    interface RuntimeBridge {
                        @KsSymbolName("kk_runtime_bridge")
                        fun bridge(): Int
                    }

                    class RuntimeBridgeImpl : RuntimeBridge

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

            // === bodylessKsSymbolNameInterfaceFunctionIsNotAbstract ===
            do {
                let sample5Diagnostics = diagnosticsForPath(paths[5], in: ctx)
                assertHasDiagnostic("KSWIFTK-SEMA-0007", in: sample5Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: sample5Diagnostics)

                let sema = try #require(ctx.sema)
                let bridge = try #require(sema.symbols.lookup(fqName: [
                    ctx.interner.intern("sample5"),
                    ctx.interner.intern("RuntimeBridge"),
                    ctx.interner.intern("bridge"),
                ]))
                #expect(!sema.symbols.symbol(bridge)!.flags.contains(.abstractType))
                #expect(sema.symbols.externalLinkName(for: bridge) == "kk_runtime_bridge")
            }
        }
    }
}
