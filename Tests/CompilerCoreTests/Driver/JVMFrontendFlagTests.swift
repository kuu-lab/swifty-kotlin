#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct JVMFrontendFlagTests {
    private func runPreparation(frontendFlags: [String]) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: "Flags",
            inputs: [],
            outputPath: "/private/tmp/flags.jar",
            emit: .jvmJar,
            target: .hostDefault(),
            frontendFlags: frontendFlags,
            stdlibOnly: true
        )
        let context = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try JVMPreparationPhase().run(context)
        return context
    }

    @Test func semaParallelFlagsAreAllowed() throws {
        for flags in [["jobs=4"], ["jobs=4", "sema-parallel"], ["jobs=4", "sema-serial"], ["sema-serial"]] {
            let context = try runPreparation(frontendFlags: flags)
            #expect(!context.diagnostics.hasError, "flags \(flags): \(context.diagnostics.diagnostics)")
        }
    }

    @Test func unsupportedFrontendFlagIsStillRejected() throws {
        let context = try runPreparation(frontendFlags: ["sema-cache"])
        #expect(context.diagnostics.hasError)
        #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-JVM-0001" })
    }
}
#endif
