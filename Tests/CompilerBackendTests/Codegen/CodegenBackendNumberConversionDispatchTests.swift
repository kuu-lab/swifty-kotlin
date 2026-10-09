#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
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

    // KUU-1372: `Number.toChar()` is the only *open* (non-abstract)
    // conversion member — its default body is `toInt().toChar()`. It was
    // missing from the kk_number_to_primitive intercept, so the call took a
    // real vtable dispatch on `Number` (an abstract class always keeps vtable
    // dispatch) and kk_vtable_lookup crashed on the metadata-less primitive
    // boxes (KSWIFTK-RUNTIME-0001). JVM truth (kotlinc -api-version 2.2):
    // 65→'A', 65.9→'A', 66L→'B', 67.5f→'C', Byte(-1)→'￿', Short(-1)→'￿'.
    @Test
    func testNumberTypedPrimitiveDispatchesToChar() throws {
        let source = """
        @Suppress("DEPRECATION", "DEPRECATION_ERROR")
        fun main() {
            val n: Number = 65
            println(n.toChar())
            val d: Number = 65.9
            println(d.toChar())
            val l: Number = 66L
            println(l.toChar())
            val f: Number = 67.5f
            println(f.toChar())
            val b: Number = (-1).toByte()
            println(b.toChar().code)
            val s: Number = (-1).toShort()
            println(s.toChar().code)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NumberTypedPrimitiveToChar",
            expected: "A\nA\nB\nC\n65535\n65535\n"
        )
    }

    // KUU-1372: same dispatch through an erased `T : Number` upper bound.
    @Test
    func testErasedNumberBoundDispatchesToChar() throws {
        let source = """
        @Suppress("DEPRECATION", "DEPRECATION_ERROR")
        fun <T : Number> firstChar(a: T, b: T): Char = if (a.toInt() >= b.toInt()) a.toChar() else b.toChar()

        fun main() {
            println(firstChar(66, 65))
        }
        """
        try assertKotlinOutput(source, moduleName: "ErasedNumberBoundToChar", expected: "B\n")
    }

    // KUU-1372: a user-defined Number subclass that does NOT override `toChar`
    // inherits the open default `toInt().toChar()`; its vtable slot 4 holds the
    // inherited body, which re-dispatches `toInt` through kk_number_to_primitive
    // and lands back on the subclass's own vtable entry. A primitive box in the
    // same program must still take the fast path.
    @Test
    func testUserNumberSubclassInheritsToCharDefault() throws {
        let source = """
        class Money(private val cents: Int) : Number() {
            override fun toDouble(): Double = cents / 100.0
            override fun toFloat(): Float = (cents / 100.0).toFloat()
            override fun toLong(): Long = (cents / 100).toLong()
            override fun toInt(): Int = cents / 100
            override fun toShort(): Short = (cents / 100).toShort()
            override fun toByte(): Byte = (cents / 100).toByte()
        }

        @Suppress("DEPRECATION", "DEPRECATION_ERROR")
        fun main() {
            val n: Number = 66
            println(n.toChar())
            val m: Number = Money(6700)
            println(m.toChar())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UserNumberSubclassInheritsToChar",
            expected: "B\nC\n"
        )
    }

    // KUU-1372: a user-defined Number subclass overriding `toChar` must have
    // its override honored through the kk_vtable_lookup fallback — the
    // intercept must not force the default `toInt().toChar()` body onto it.
    @Test
    func testUserNumberSubclassToCharOverrideWins() throws {
        let source = """
        class Weird(private val raw: Int) : Number() {
            override fun toChar(): Char = 'Z'
            override fun toDouble(): Double = raw.toDouble()
            override fun toFloat(): Float = raw.toFloat()
            override fun toLong(): Long = raw.toLong()
            override fun toInt(): Int = raw
            override fun toShort(): Short = raw.toShort()
            override fun toByte(): Byte = raw.toByte()
        }

        @Suppress("DEPRECATION", "DEPRECATION_ERROR")
        fun main() {
            val n: Number = 65
            println(n.toChar())
            val w: Number = Weird(66)
            println(w.toChar())
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "UserNumberSubclassToCharOverride",
            expected: "A\nZ\n"
        )
    }
}
#endif
