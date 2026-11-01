#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct DuplicateFunKeywordParsingTests {
    @Test(arguments: [
        "fun tailrec fun tr(n: Int): Int = n",
        "fun private fun g() {}",
        "fun inline fun h() {}",
    ])
    func rejectsSecondFunKeywordBeforeFunctionName(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        let diagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-PARSE-0002"
        }

        #expect(diagnostics.count >= 1)
        #expect(diagnostics.first?.severity == .error)
    }

    @Test
    func newlineSeparatedFunctionsStillRejectWithoutParseError() throws {
        // `fun tailrec` / `fun tr` on separate lines parses as two declarations;
        // the bodiless `tailrec` fails in sema rather than the parser.
        try withTemporaryFile(contents: "fun tailrec\nfun tr(n: Int): Int = n") { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0009" })
            assertNoDiagnostic("KSWIFTK-PARSE-0002", in: context)
        }
    }

    @Test
    func normalFunctionsAndLocalFunctionsStayValid() throws {
        let source = """
        tailrec fun tr(n: Int): Int = if (n <= 0) 0 else tr(n - 1)
        private fun g() = 1
        fun outer() {
            fun inner() {}
        }
        """
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        assertNoDiagnostic("KSWIFTK-PARSE-0002", in: context)
        #expect(!context.diagnostics.hasError)
    }
}
#endif
