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
    irFlags: [String] = [],
    allowDefaultStdlibLibrary: Bool = true
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags,
        allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
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
        expected: String,
        allowDefaultStdlibLibrary: Bool = true
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map(\.message))")
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

        // Subclassing a bundled class only works through bundled-source
        // injection: modality is lost when the same class is imported from a
        // precompiled stdlib artifact (BUG-183).
        try assertKotlinOutput(
            source,
            moduleName: "AbstractIteratorSubclassRuntime",
            expected: "42\n",
            allowDefaultStdlibLibrary: false
        )
    }

    /// A generic nullable backing field must preserve boxed primitive values,
    /// nullable values, and reference values across repeated stores and loads.
    @Test
    func testGenericNullableFieldPreservesStoredValuesAcrossTypesAndCalls() throws {
        let source = """
        import kotlin.collections.AbstractIterator

        abstract class NullableSlot<T> {
            private var value: T? = null

            fun store(next: T) {
                value = next
            }

            @Suppress("UNCHECKED_CAST")
            fun load(): T {
                val result = value as T
                value = null
                return result
            }
        }

        class IntSlot : NullableSlot<Int>()
        class LongSlot : NullableSlot<Long>()
        class StringSlot : NullableSlot<String>()
        class BooleanSlot : NullableSlot<Boolean>()
        class NullableStringSlot : NullableSlot<String?>()

        class Label(val text: String)
        class LabelSlot : NullableSlot<Label>()

        class OneShot(private val value: Int) : AbstractIterator<Int>() {
            private var used = false

            override fun computeNext() {
                if (used) {
                    done()
                } else {
                    used = true
                    setNext(value)
                }
            }
        }

        fun main() {
            val iterator = OneShot(42)
            while (iterator.hasNext()) {
                println(iterator.next())
            }

            val ints = IntSlot()
            ints.store(42)
            println(ints.load())
            ints.store(7)
            println(ints.load())

            val longs = LongSlot()
            longs.store(9000000000L)
            println(longs.load())

            val strings = StringSlot()
            strings.store("source")
            println(strings.load().length)

            val booleans = BooleanSlot()
            booleans.store(true)
            println(booleans.load())

            val nullable = NullableStringSlot()
            nullable.store(null)
            println(nullable.load() == null)
            nullable.store("nullable-value")
            println(nullable.load()?.length)

            val labels = LabelSlot()
            labels.store(Label("member"))
            println(labels.load().text)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "GenericNullableFieldRuntime",
            expected: "42\n42\n7\n9000000000\n6\ntrue\ntrue\n14\nmember\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
