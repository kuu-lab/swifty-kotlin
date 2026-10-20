#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func genericNumericCarriersUnboxBeforePromotion(mode: EmitMode) throws {
        try assertJVM("""
        fun <T : Double> f(v: T) = v * v
        fun <T : Double> g(v: T): Double = v * 1.0
        fun <T : Float> floatSquare(v: T) = v * v
        fun <T : Float> floatWiden(v: T): Double = v * 1.0
        fun <T : Int> intSquare(v: T) = v * v
        fun <T : Int> intWiden(v: T): Double = v * 1.0
        fun <T : Long> longSquare(v: T) = v * v
        fun <T : Long> longWiden(v: T): Double = v * 1.0
        fun <T : Byte> byteSquare(v: T) = v * v
        fun <T : Short> shortSquare(v: T) = v * v
        fun <T : Char> next(v: T) = v + 1
        fun <T : Char> distance(v: T) = v - v
        fun <T : Double> lower(v: T) = v < 3.0
        fun <T : Float> converted(v: T): Double = v.toDouble()
        fun main() {
            println(f(2.0)); println(g(2.0))
            println(floatSquare(2.0f)); println(floatWiden(2.0f))
            println(intSquare(2)); println(intWiden(2))
            println(longSquare(2L)); println(longWiden(2L))
            println(byteSquare(2.toByte())); println(shortSquare(2.toShort()))
            println(next('b')); println(distance('b'))
            println(lower(2.0)); println(converted(2.0f))
            val nullable: Double? = 2.0
            println(nullable!! * nullable!!)
            val erased: Any = 1.0
            try { println(erased as Int) } catch (e: ClassCastException) { println("cast") }
        }
        """, "4.0\n2.0\n4.0\n2.0\n4\n2.0\n4\n2.0\n4\n4\nc\n0\ntrue\n2.0\n4.0\ncast\n", mode: mode)
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func numericCarrierSafeCompareToUsesEvaluatedReceiver(mode: EmitMode) throws {
        try assertJVM("""
        fun receiver(v: Byte?): Byte? { print("R"); return v }
        fun argument(): Double { print("A"); return 2.0 }
        fun Byte.compareTo(other: String): Int = other.length
        fun <T : Comparable<T>> compare(a: T, b: T) = a.compareTo(b)
        fun main() {
            println(receiver(1)?.compareTo(argument()))
            println(receiver(null)?.compareTo(argument()))
            val short: Short? = -32768
            println(short?.compareTo(-32768.5f))
            println(short?.compareTo(32767L))
            val absent: Short? = null
            println(absent?.compareTo(argument()))
            val comparator: (Byte, Double) -> Int = { a, b -> a.compareTo(b) }
            println(comparator(-128, -127.5))
            println(compare(1.toByte(), 2.toByte()))
            val comparable: Comparable<Byte> = 1.toByte()
            println(comparable.compareTo(2.toByte()))
            println(1.toByte().compareTo("abcd"))
        }
        """, "RA-1\nRnull\n1\n-1\nnull\n-1\n-1\n-1\n4\n", mode: mode)
    }

    @Test(arguments: [
        "fun <T : Any> bad(v: T) = v * v",
        "fun <T : Number> bad(v: T) = v * v",
        "fun <T : Double?> bad(v: T) = v * v",
        "fun <T : Number?> bad(v: T) = v * v",
    ])
    func numericCarrierRecognitionDoesNotAcceptNonNumericBounds(source: String) throws {
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.severity == .error })
            #expect(!result.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
