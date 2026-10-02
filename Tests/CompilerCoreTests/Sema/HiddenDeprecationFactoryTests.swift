@testable import CompilerCore
import Testing

@Suite
struct HiddenDeprecationFactoryTests {
    @Test
    func hiddenFactoryDoesNotShadowConstructor() throws {
        let source = """
        class Token(val value: Int)
        @Deprecated("compatibility", level = DeprecationLevel.HIDDEN)
        fun Token(value: Int): Token = Token(value)
        fun main() { println(Token(7).value) }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-DEPRECATED", in: ctx)
            #expect(!ctx.diagnostics.hasError)
        }
    }

    @Test
    func hiddenFunctionCannotBeCalled() throws {
        let source = """
        @Deprecated("compatibility", level = DeprecationLevel.HIDDEN)
        fun removed(): Int = 7
        fun main() { println(removed()) }
        """
        try withTemporaryFiles(contents: [source]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }
}
