@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenObjectMemberFunctionImportTests {
    @Test(arguments: [0, 2])
    func directAndAliasedImportsAcrossFiles(optimization: Int) throws {
        try withTemporaryFiles(contents: [
            """
            package views
            object Factories {
                private var count = 10
                fun <T> freeze(values: List<T>): List<T> = values
                fun next(step: Int = 1): Int { count += step; return count }
            }
            object Numbers {
                fun convert(value: Int): Int = value + 1
                fun convert(value: Int, block: (Int) -> Int): Int = block(value)
            }
            object Words {
                fun convert(value: String): String = value + "!"
                fun convert(value: String, block: (String) -> String): String = block(value)
            }
            """,
            """
            import views.Factories.freeze
            import views.Factories.freeze as frozenCopy
            import views.Factories.next as nextValue
            import views.Factories
            import views.Factories as Views
            import views.Numbers.convert
            import views.Words.convert

            class Reader { fun read(): Int = nextValue(2) }
            fun String.read(): Int = nextValue()
            fun Factories?.readNullable(): Int = nextValue()
            fun main() {
                val values = listOf("a", "b")
                println(freeze(values))
                println(frozenCopy<String>(values))
                println(Factories.freeze(values))
                println(Views.freeze(values))
                println(nextValue())
                println(Reader().read())
                println("receiver".read())
                val nullable: Factories? = null
                println(nullable.readNullable())
                println(convert(3))
                println(convert("ok"))
                println(convert(3) { it + 2 })
                println(convert("ok") { it + "?" })
                val frozenCopy: (Int) -> Int = { it + 10 }
                println(frozenCopy(2))
            }
            """,
        ]) { paths in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let output = directory.appendingPathComponent("consumer").path
            let options = CompilerOptions(
                moduleName: "ObjectMemberFunctionImport",
                inputs: paths,
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: false,
                stdlibLibraryPath: try testStdlibArtifactPath(),
                allowDefaultStdlibLibrary: false
            )
            #expect(!options.includeStdlib)
            #expect(options.stdlibLibraryPath != nil)
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "[a, b]\n[a, b]\n[a, b]\n[a, b]\n11\n13\n14\n15\n4\nok!\n5\nok?\n12\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
