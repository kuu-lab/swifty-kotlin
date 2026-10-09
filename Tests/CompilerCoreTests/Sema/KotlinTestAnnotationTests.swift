@testable import CompilerCore
import Testing
import TestStdlibCache

struct KotlinTestAnnotationTests {
    @Test(arguments: [
        "@kotlin.test.Test class Invalid",
        "@kotlin.test.BeforeTest class Invalid",
        "@kotlin.test.AfterTest class Invalid",
        "@kotlin.test.Ignore val invalid = 1",
    ], [true, false])
    func rejectsInvalidAnnotationTarget(source: String, useArtifact: Bool) {
        let ctx = makeContext(source, useArtifact: useArtifact)
        do {
            try runSema(ctx)
        } catch {
            // Invalid targets are expected to stop the Sema phase.
        }
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-ANNOTATION-TARGET")
    }

    @Test(arguments: [true, false])
    func experimentalApiRequiresOptIn(useArtifact: Bool) {
        let ctx = makeContext("""
        @kotlin.test.ExperimentalKotlinTestApi
        fun experimental() = 1
        fun caller() = experimental()
        """, useArtifact: useArtifact)
        do {
            try runSema(ctx)
        } catch {
            // The call without opt-in is expected to stop the Sema phase.
        }
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(ctx.diagnostics.diagnostics)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-OPT-IN")
    }

    private func makeContext(_ source: String, useArtifact: Bool) -> CompilationContext {
        if useArtifact {
            TestStdlibCache.shared.prepare()
        }
        return makeContextFromSource(
            source,
            emit: .executable,
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
