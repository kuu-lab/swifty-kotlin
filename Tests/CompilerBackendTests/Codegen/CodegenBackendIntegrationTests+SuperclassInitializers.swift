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
    try CodegenPhase().run(ctx)
    return ctx
}

/// BUG-155: a primary constructor must run the superclass constructor before
/// its own initializers, so inherited property initializers, `init` blocks and
/// superclass constructor arguments are visible on subclass instances.
@Suite
struct CodegenSuperclassInitializerTests {

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

    @Test
    func testSubclassSeesInheritedPropertyInitializersAndSuperConstructorArgs() throws {
        let source = """
        open class Base(val label: String) {
            var counter: Int = 7
            init { counter = counter + 1 }
        }

        class Child(label: String, val extra: Int) : Base(label) {
            var own: Int = 3
        }

        fun main() {
            val child = Child("root", 5)
            println(child.label)
            println(child.counter)
            println(child.extra)
            println(child.own)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SuperclassInitializerRuntime",
            expected: "root\n8\n5\n3\n"
        )
    }

    @Test
    func testSecondaryConstructorRunsClassBodyInitializers() throws {
        let source = """
        open class Counter {
            var hits: Int = 2
        }

        class SecondaryOnly : Counter {
            var name: String = "secondary"

            constructor() : super() { hits = hits + 5 }

            constructor(extra: Int) : this() { hits = hits + extra }
        }

        fun main() {
            val secondary = SecondaryOnly()
            println(secondary.hits)
            println(secondary.name)
            println(SecondaryOnly(10).hits)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SecondaryConstructorInitializerRuntime",
            expected: "7\nsecondary\n17\n"
        )
    }

    /// The reported BUG-155 reproducer: a user-defined `AbstractIterator`
    /// subclass returned `0` instead of the value passed to `setNext`, because
    /// `AbstractIterator`'s `state` field kept its zeroed default.
    @Test
    func testUserDefinedAbstractIteratorSubclassYieldsStoredValue() throws {
        let source = """
        import kotlin.collections.AbstractIterator

        class OneShot(private val v: Int) : AbstractIterator<Int>() {
            private var used = false
            override fun computeNext() {
                if (used) done() else { used = true; setNext(v) }
            }
        }

        fun main() {
            val it = OneShot(42)
            while (it.hasNext()) println(it.next())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AbstractIteratorSubclassRuntime",
            expected: "42\n"
        )
    }
}
#endif
