#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CompanionMemberExtensionImportTests {
    private let declaration = """
        package sample.library
        class Token(val x: Int) {
            companion object {
                inline fun Token.wrapCause(w: (Int) -> Int = { it }): Int = w(x)
            }
        }
        """

    @Test func testImportedCompanionMemberExtensionResolvesAndLowers() throws {
        let usage = """
            package sample.usage
            import sample.library.Token
            import sample.library.Token.Companion.wrapCause

            fun use(t: Token): Int = t.wrapCause()
            fun useWithArgument(t: Token): Int = t.wrapCause { it + 1 }
            """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test func testUnimportedCompanionMemberExtensionIsNotGloballyVisible() throws {
        let usage = """
            package sample.usage
            import sample.library.Token

            fun use(t: Token): Int = t.wrapCause()
            """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0024", in: diagnosticsForPath(paths[1], in: ctx))
        }
    }

    @Test(arguments: [false, true])
    func companionExtensionPropertyRequiresImport(imported: Bool) throws {
        let declaration = """
        package sample.library
        class Token {
            companion object {
                val Int.doubled: Int get() = this * 2
            }
        }
        """
        let usage = """
        package sample.usage
        \(imported ? "import sample.library.Token.Companion.doubled" : "import sample.library.*")
        fun use(): Int = 3.doubled
        """
        try withTemporaryFiles(contents: [declaration, usage]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError == !imported, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
