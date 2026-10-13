@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func kClassModalityAndSingletons(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kclass_modality_and_singletons.kt", file: #filePath),
            expectedOutput: "2\ntrue\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\nfalse\ntrue\n0\ntrue\n1\ntrue\ntrue\n42\ntrue\ntrue\n7\n0\n2\ntrue\ntrue\nfalse\n2\n0\ntrue\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\nfalse\nfalse\n",
            moduleName: "KUU1315KClassModality",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    @Test(arguments: [true, false])
    func kClassObjectInstancePropagatesInitializationFailure(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KClass
            object Broken { init { throw IllegalStateException("init failed") } }
            fun main() {
                val k: KClass<*> = Broken::class
                try {
                    k.objectInstance
                    println("unexpected")
                } catch (e: IllegalStateException) {
                    println(e.message)
                }
            }
            """,
            expectedOutput: "init failed\n",
            moduleName: "KUU1315ObjectInitFailure",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }

    @Test func kClassImportedObjectInstance() throws {
        try withCompiledLibrary(source: """
            package reflectionLib
            var initialized = 0
            object Obj {
                init { initialized += 1 }
                val value = 42
            }
            class Owner { companion object { val value = 7 } }
            sealed class Root
            class Child : Root()
            """, moduleName: "KClassSingletonLibrary") { library in
            try withTemporaryFile(contents: """
                import kotlin.reflect.KClass
                import reflectionLib.*
                fun main() {
                    val k: KClass<*> = Obj::class
                    println(initialized)
                    println(k.objectInstance === Obj)
                    println(initialized)
                    println(Obj::class.objectInstance?.value)
                    println(Owner.Companion::class.objectInstance === Owner.Companion)
                    println(Owner.Companion::class.objectInstance?.value)
                    println(Root::class.sealedSubclasses.contains(Child::class))
                }
                """) { source in
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
                defer { try? FileManager.default.removeItem(atPath: output) }
                let options = CompilerOptions(
                    moduleName: "KClassSingletonConsumer", inputs: [source], outputPath: output,
                    emit: .executable, searchPaths: [library], target: defaultTargetTriple()
                )
                try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
                let result = try CommandRunner.run(executable: output, arguments: [])
                #expect(result.exitCode == 0)
                #expect(result.stdout == "0\ntrue\n1\n42\ntrue\n7\ntrue\n")
            }
        }
    }
}
