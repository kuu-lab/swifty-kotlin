#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct IntroducedAtVersionOverloadingTests {
    @Test
    func multilineAnnotatedDefaultParametersKeepFunctionBody() throws {
        let source = """
        @file:OptIn(ExperimentalVersionOverloading::class)
        fun g(value: String): Int = 1
        fun f(value: String = "a",
              @IntroducedAt("1") transform: (String) -> Int = ::g,
              @IntroducedAt("2") result: Int = transform(value)): Int = result
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)

            let diagnostics = diagnosticsForPath(path, in: ctx)
            #expect(!diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
            #expect(!diagnostics.contains { $0.code == "KSWIFTK-SEMA-0009" })
        }
    }
}
#endif
