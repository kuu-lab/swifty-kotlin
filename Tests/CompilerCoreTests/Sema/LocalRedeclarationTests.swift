@testable import CompilerCore
import Testing

@Suite
struct LocalRedeclarationTests {
    @Test
    func sameScopeLocalValuesAndClassifiersCannotRedeclareNames() throws {
        let source = """
        fun duplicateVals() {
            val x = 1
            val x = 2
        }
        fun duplicateValAndVar() {
            val x = 1
            var x = 2
        }
        fun duplicateVarAndVal() {
            var x = 1
            val x = 2
        }
        fun duplicateValueAndClass() {
            val Local = 1
            class Local
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            let conflicts = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0001" && $0.message.contains("Conflicting local declarations")
            }
            #expect(conflicts.count == 4, "Expected one diagnostic for each redeclaration, got \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func nestedShadowingAndLocalFunctionNameSharingRemainValid() throws {
        let source = """
        fun main() {
            val x = 1
            if (true) {
                val x = 2
            }
            fun x() = 2
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func separateTopLevelAccessorBodiesHaveIndependentLocalScopes() throws {
        let source = """
        val first: Int
            get() {
                val value = 1
                return value
            }
        val second: Int
            get() {
                val value = 2
                return value
            }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        }
    }
}
