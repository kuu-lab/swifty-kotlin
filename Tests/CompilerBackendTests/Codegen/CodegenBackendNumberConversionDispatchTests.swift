#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendNumberConversionDispatchTests {

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: moduleName,
                inputs: [path],
                outputPath: outputBase,
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
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    // KSP-1540 / DEBT-DIFF-008: a primitive assigned to a `Number`-typed
    // variable dispatches `toDouble/toFloat/toLong/toInt/toShort/toByte`
    // through the abstract `kotlin.Number` declaration. Before the fix this
    // silently returned zero for every conversion (CallLowerer+
    // NumberConversionMemberCalls.swift / kk_number_to_primitive).
    @Test
    func testNumberTypedPrimitiveDispatchesAllConversions() throws {
        let source = """
        fun main() {
            val n: Number = 42
            println(n.toDouble())
            println(n.toFloat())
            println(n.toLong())
            println(n.toInt())
            println(n.toShort())
            println(n.toByte())

            val d: Number = 3.75
            println(d.toDouble())
            println(d.toFloat())
            println(d.toLong())
            println(d.toInt())
            println(d.toShort())
            println(d.toByte())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumberTypedPrimitiveDispatch",
            expected: "42.0\n42.0\n42\n42\n42\n42\n3.75\n3.75\n3\n3\n3\n3\n"
        )
    }

    // Same dispatch problem through an erased `T : Number` upper bound
    // instead of a concretely `Number`-typed variable — the second gate case
    // for DEBT-DIFF-008 (stdlib_kotlin_n_Number_primitive_generic.kt).
    @Test
    func testErasedNumberBoundDispatchesToDouble() throws {
        let source = """
        fun <T : Number> sumOf(a: T, b: T): Double = a.toDouble() + b.toDouble()

        fun main() {
            println(sumOf(40, 2))
        }
        """
        try assertKotlinOutput(source, moduleName: "ErasedNumberBoundDispatch", expected: "42.0\n")
    }

    // A boxed primitive and a genuine user-defined `Number` subclass must
    // coexist correctly through the same abstract dispatch point: the
    // primitive takes the native-conversion fast path in
    // kk_number_to_primitive, the user subclass falls back to its own real
    // vtable slot (kk_vtable_lookup). Before the fix, once any Number
    // subtype was visible in the program, resolveVtableDispatch stopped
    // declining and routed the primitive through a genuine vtable lookup —
    // which crashed (KSWIFTK-RUNTIME-0001) because the built-in boxes carry
    // no compiler-synthesized class metadata.
    @Test
    func testPrimitiveAndUserDefinedNumberSubclassCoexist() throws {
        let source = """
        class Money(private val cents: Int) : Number() {
            override fun toDouble(): Double = cents / 100.0
            override fun toFloat(): Float = (cents / 100.0).toFloat()
            override fun toLong(): Long = (cents / 100).toLong()
            override fun toInt(): Int = cents / 100
            override fun toShort(): Short = (cents / 100).toShort()
            override fun toByte(): Byte = (cents / 100).toByte()
        }

        fun describe(n: Number): Double = n.toDouble()

        fun main() {
            val n: Number = 42
            println(n.toInt())

            val m: Number = Money(750)
            println(describe(m))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveAndUserNumberSubclassCoexist",
            expected: "42\n7.5\n"
        )
    }
}
#endif
