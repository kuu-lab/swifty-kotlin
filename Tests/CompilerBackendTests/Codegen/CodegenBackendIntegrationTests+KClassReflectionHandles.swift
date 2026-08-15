#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runKClassReflectionHandlesPipeline(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
        target: defaultTargetTriple()
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

@Suite
struct CodegenBackendKClassReflectionHandlesTests {
    @Test
    func kClassReflectionHandlesSupportNominalChecksAndCallableName() throws {
        let source = """
        import kotlin.reflect.KCallable
        import kotlin.reflect.KFunction
        import kotlin.reflect.KProperty
        import kotlin.reflect.full.*

        class ReflectionSample(val value: Int) {
            fun increment(): Int = value + 1
        }

        fun main() {
            val klass = ReflectionSample::class
            val member = klass.members.firstOrNull()
            println(member is KCallable<*>)
            println(!(member as? KCallable<*>)?.name.isNullOrEmpty())

            val constructor = klass.constructors.firstOrNull()
            println(constructor is KCallable<*>)
            println(!(constructor as? KCallable<*>)?.name.isNullOrEmpty())

            val primary = klass.primaryConstructor
            println(primary is KFunction<*>)
            println(!(primary as? KCallable<*>)?.name.isNullOrEmpty())

            val property = klass.properties.firstOrNull()
            println(property is KProperty<*>)
            println(!(property as? KCallable<*>)?.name.isNullOrEmpty())

            println(klass.memberProperties.isNotEmpty())
            println(klass.declaredMemberProperties.isNotEmpty())

            val function = klass.functions.firstOrNull()
            println(function is KFunction<*>)
            println(!(function as? KCallable<*>)?.name.isNullOrEmpty())
            println(klass.memberFunctions.isNotEmpty())
            println(klass.declaredMemberFunctions.isNotEmpty())
            println(klass.nestedClasses.isEmpty())
            println(klass.supertypes.isNotEmpty())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runKClassReflectionHandlesPipeline(
                inputPath: path,
                moduleName: "KClassReflectionHandles",
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == """
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                true
                """ + "\n"
            )
        }
    }
}
#endif
