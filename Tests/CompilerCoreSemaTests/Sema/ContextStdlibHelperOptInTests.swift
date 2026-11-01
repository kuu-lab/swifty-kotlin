#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ContextStdlibHelperOptInTests {
    // KUU-3781: kotlin-stdlib 2.4.20 carries no
    // @ExperimentalContextParameters on the `context`/`contextOf` helper
    // overloads, so calling them must not require @OptIn. The bundled copy
    // still had the marker and reported KSWIFTK-SEMA-OPT-IN on every
    // `context(...) { }` call.
    @Test
    func contextScopeHelpersDoNotRequireOptIn() throws {
        try withTemporaryFile(contents: """
        fun useContextHelpers(): String =
            context("one") { contextOf<String>() } +
                context(1, 2) { contextOf<Int>().toString() }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        }
    }

    // The marker itself still gates user-declared APIs — matching kotlinc,
    // which keeps @RequiresOptIn on ExperimentalContextParameters.
    @Test
    func userDeclaredContextMarkerStillRequiresOptIn() throws {
        try withTemporaryFile(contents: """
        @kotlin.ExperimentalContextParameters
        fun markedApi(): Int = 1

        fun caller(): Int = markedApi()
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-OPT-IN"
            }, "\(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
