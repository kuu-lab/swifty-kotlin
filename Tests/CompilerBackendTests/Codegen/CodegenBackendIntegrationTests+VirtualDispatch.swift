#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

private func assertKotlinOutput(
    _ source: String,
    moduleName: String,
    expected: String
) throws {
    try withTemporaryFile(contents: source) { path in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let ctx = try runCodegenPipeline(
            inputPath: path,
            moduleName: moduleName,
            emit: .executable,
            outputPath: outputBase
        )
        try LinkPhase().run(ctx)
        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        let normalizedStdout = result.stdout
            .replacingOccurrences(of: "\r\n", with: "\n")
        #expect(normalizedStdout == expected)
    }
}

@Suite
struct CodegenBackendVirtualDispatchTests {

    @Test
    func testOpenClassVirtualDispatchChoosesConcreteOverride() throws {
        let source = """
        open class Animal {
            open fun speak(): String = "base"
        }
        class Dog : Animal() {
            override fun speak(): String = "dog"
        }
        class Cat : Animal() {
            override fun speak(): String = "cat"
        }
        fun callSpeak(animal: Animal): String = animal.speak()
        fun main() {
            println(callSpeak(Dog()))
            println(callSpeak(Cat()))
            println(callSpeak(Animal()))
        }
        """
        try assertKotlinOutput(source, moduleName: "OpenClassVirtualDispatchRuntime", expected: "dog\ncat\nbase\n")
    }

    // BUG-156: the interface method implemented by the abstract base must be
    // reachable through the concrete subclass' itable, and the base's
    // unqualified `compute()` must reach the subclass override.
    @Test
    func testInterfaceMethodInheritedFromAbstractBaseDispatchesThroughItable() throws {
        let source = """
        interface Box<T> {
            fun get(): T
        }
        abstract class AbstractBox<T> : Box<T> {
            abstract fun compute(): T
            override fun get(): T = compute()
        }
        class IntBox(val v: Int) : AbstractBox<Int>() {
            override fun compute(): Int = v
        }
        fun accept(b: Box<Int>): Int = b.get()
        fun main() {
            val box = IntBox(7)
            println(box.get())
            println(accept(box))
        }
        """
        try assertKotlinOutput(source, moduleName: "InheritedInterfaceItableDispatchRuntime", expected: "7\n7\n")
    }

    @Test
    func testUnqualifiedSelfCallDispatchesToSubclassOverride() throws {
        let source = """
        abstract class Greeter {
            abstract fun name(): String
            fun greet(): String = "hello " + name()
        }
        class Named : Greeter() {
            override fun name(): String = "world"
        }
        fun main() {
            println(Named().greet())
        }
        """
        try assertKotlinOutput(source, moduleName: "UnqualifiedSelfCallDispatchRuntime", expected: "hello world\n")
    }
}
#endif
