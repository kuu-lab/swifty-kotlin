@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func kotlinJsCreateInstanceUsesSharedConstructorPath(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.js.ExperimentalJsReflectionCreateInstance::class)
            import kotlin.reflect.createInstance

            var defaultEvaluationCount = 0
            fun nextDefaultValue(): Int {
                defaultEvaluationCount += 1
                return 40 + defaultEvaluationCount
            }

            class ExportedBox(val value: Int = 7)
            class NoArgBox(val value: Int) {
                constructor() : this(42)
            }
            class SideEffectDefault(val value: Int = nextDefaultValue())
            class RequiredConstructor(val value: Int)
            class MultipleEligibleConstructors(val value: Int = 7) {
                constructor() : this(42)
            }

            fun main() {
                println(ExportedBox::class.createInstance().value)
                println(NoArgBox::class.createInstance().value)
                println(SideEffectDefault::class.createInstance().value)
                println(defaultEvaluationCount)
                println(SideEffectDefault::class.createInstance().value)
                println(defaultEvaluationCount)

                val createInstanceReference = ExportedBox::class::createInstance
                println("${ExportedBox::class.simpleName}:${createInstanceReference.name}:${ExportedBox::class.createInstance().value}")

                try {
                    RequiredConstructor::class.createInstance()
                    println("required:unexpected")
                } catch (error: IllegalArgumentException) {
                    println("required:rejected")
                }

                try {
                    MultipleEligibleConstructors::class.createInstance()
                    println("multiple:unexpected")
                } catch (error: IllegalArgumentException) {
                    println("multiple:rejected")
                }
            }
            """,
            expectedOutput: "7\n42\n41\n1\n42\n2\nExportedBox:createInstance:7\nrequired:rejected\nmultiple:rejected\n",
            moduleName: "KotlinJSReflectionCreateInstance",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func kotlinJsCreateInstanceOptInIsAvailableFromSourceAndLibraryMetadata(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let source = """
        import kotlin.reflect.createInstance

        class Box
        fun instantiate() = Box::class.createInstance()
        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase + ".kir") }

            let options = makeTestOptions(
                moduleName: "KotlinJSReflectionCreateInstanceOptIn",
                inputs: [inputPath],
                outputPath: outputBase,
                emit: .kirDump,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            let result = makeTestDriver().runForTesting(options: options)
            let optInDiagnostics = result.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-OPT-IN"
            }

            #expect(result.exitCode == 0, "Compilation failed: \(result.diagnostics)")
            #expect(optInDiagnostics.count == 1, "Expected a createInstance opt-in warning, got: \(result.diagnostics)")
            #expect(optInDiagnostics.allSatisfy {
                if case .warning = $0.severity { return true }
                return false
            }, "ExperimentalJsReflectionCreateInstance should require warning-level opt-in")
        }
    }
}
