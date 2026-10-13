@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testKClassFullCastsOriginalReproducer(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("stdlib_kotlin_reflect_KClass_n.kt", file: #filePath),
            expectedOutput: "hello\n7\ngeneric\nnull\n3\nnull\nvia local\ntrue\ntrue\nnull\ncaught\n",
            moduleName: "KUU1975Original",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testKClassFullCastsExplicitAndAliasedImports(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kclass_reflect_full_cast_imports.kt", file: #filePath),
            expectedOutput: "5\n8\n5\n9\n3\nnull\nnull\nnull\nnull\nwrong:TypeCastException\nnull:TypeCastException\n",
            moduleName: "KUU1975Imports",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testKClassFullCastsSafeResultRemainsNullable(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        import kotlin.reflect.full.safeCast as safeCastFromFull
        fun invalid(): String = String::class.safeCastFromFull("hello")
        """
        try withTemporaryFile(contents: source) { path in
            let options = makeTestOptions(
                moduleName: "KUU1975NullableResult",
                inputs: [path],
                outputPath: path + ".out",
                emit: .executable,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(result.exitCode != 0)
            let errors = result.diagnostics.filter { $0.severity == .error }
            #expect(errors.count == 1)
            #expect(errors.first?.code == "KSWIFTK-TYPE-0001")
        }
    }
}
