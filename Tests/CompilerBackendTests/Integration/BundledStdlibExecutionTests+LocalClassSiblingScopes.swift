@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testLocalClassSiblingScopes(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("local_class_sibling_scopes.kt", file: #filePath),
            expectedOutput: "a=1\ngot=5\nfirst\n10\nsecond\n20\n80\n70\n",
            moduleName: "KUU1971LocalClassSiblingScopes",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testLocalClassOrdinaryBlockScopes() throws {
        try compileAndRunKotlin(
            try repositoryFileSource(
                "Tests/CompilerBackendTests/Fixtures/basic/local_class_block_scopes/local_class_block_scopes.kt",
                file: #filePath
            ),
            expectedOutput: "30\n40\n50\n60\n90\n100\n",
            moduleName: "KUU1971LocalClassBlockScopes"
        )
    }
}
