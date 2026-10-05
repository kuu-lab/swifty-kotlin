#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendPrimitiveCompareToTests {

    @Test
    func testByteAndShortCompareToAllSignedNumericTypes() throws {
        let source = """
        fun byteComparisons(b: Byte, s: Short, i: Int, l: Long, f: Float, d: Double) {
            println(b.compareTo(b))
            println(b.compareTo(s))
            println(b.compareTo(i))
            println(b.compareTo(l))
            println(b.compareTo(f))
            println(b.compareTo(d))
        }
        fun shortComparisons(s: Short, b: Byte, i: Int, l: Long, f: Float, d: Double) {
            println(s.compareTo(b))
            println(s.compareTo(s))
            println(s.compareTo(i))
            println(s.compareTo(l))
            println(s.compareTo(f))
            println(s.compareTo(d))
        }
        fun main() {
            byteComparisons(1, 2, 2, 2L, 1.5f, 1.5)
            shortComparisons(2, 1, 3, 3L, 2.5f, 2.5)
            println(1.toByte().compareTo(2))
            println(1.toShort().compareTo(2))
            println(Byte.MIN_VALUE.compareTo(Byte.MAX_VALUE))
            println(Short.MAX_VALUE.compareTo(Short.MIN_VALUE))
            println(Byte.MAX_VALUE.compareTo(Long.MIN_VALUE))
            println(Short.MIN_VALUE.compareTo(Long.MAX_VALUE))
            println(Short.MAX_VALUE.compareTo(65536L))
            println(Byte.MIN_VALUE.compareTo(-128.0))
            println(0.toByte().compareTo(-0.0))
            println(0.toShort().compareTo(-0.0f))
            println(1.toByte().compareTo(Double.NaN))
            println(1.toShort().compareTo(Float.POSITIVE_INFINITY))
        }
        """
        try assertKotlinOutput(source, moduleName: "NarrowPrimitiveCompareTo", expected: "0\n-1\n-1\n-1\n-1\n-1\n1\n0\n-1\n-1\n-1\n-1\n-1\n-1\n-1\n1\n1\n-1\n-1\n0\n1\n1\n-1\n-1\n")
    }

    @Test
    func testByteAndShortCompareToPreservesSafeCallsAndGenericDispatch() throws {
        let source = """
        fun <T : Comparable<T>> compare(a: T, b: T): Int = a.compareTo(b)
        fun receiver(value: Byte?): Byte? {
            println("receiver")
            return value
        }
        fun argument(): Double {
            println("argument")
            return 2.0
        }
        fun main() {
            println(receiver(1)?.compareTo(argument()))
            println(receiver(null)?.compareTo(argument()))
            val short: Short? = -32768
            println(short?.compareTo(Long.MAX_VALUE))
            println(short?.compareTo(-32768.5f))
            val absent: Short? = null
            println(absent?.compareTo(argument()))
            println(compare(Byte.MIN_VALUE, Byte.MAX_VALUE))
            println(compare(Short.MAX_VALUE, Short.MIN_VALUE))
            val byteComparable: Comparable<Byte> = Byte.MIN_VALUE
            val shortComparable: Comparable<Short> = Short.MAX_VALUE
            println(byteComparable.compareTo(Byte.MAX_VALUE))
            println(shortComparable.compareTo(Short.MIN_VALUE))
            val comparator: (Byte, Double) -> Int = { a, b -> a.compareTo(b) }
            println(comparator(-128, -127.5))
        }
        """
        try assertKotlinOutput(source, moduleName: "NarrowPrimitiveCompareToSafeCall", expected: "receiver\nargument\n-1\nreceiver\nnull\n-1\n1\nnull\n-1\n1\n-1\n1\n-1\n")
    }

    @Test
    func testCodegenCompilesMixedFloatingPointCompareTo() throws {
        let source = """
        fun main() {
            println(1.5.compareTo(2))
            println(1.5.compareTo(2L))
            println(2.0.compareTo(3))
            println(1.5f.compareTo(2))
            println(1.5f.compareTo(2.0))
            println(2.0.compareTo(4607182418800017408L))
            println(1.5.compareTo(2f))
            println(1.5f.compareTo(2L))
            val byte: Byte = 2
            val short: Short = 2
            println(1.5.compareTo(byte))
            println(1.5.compareTo(short))
            println(1.5f.compareTo(byte))
            println(1.5f.compareTo(short))
        }
        """
        try assertKotlinOutput(source, moduleName: "MixedFloatingPointCompareTo", expected: String(repeating: "-1\n", count: 12))
    }

    @Test
    func testMixedFloatingPointCompareToPreservesTotalOrderAndPromotion() throws {
        let source = """
        fun compareDouble(a: Double, b: Long): Int = a.compareTo(b)
        fun compareFloat(a: Float, b: Double): Int = a.compareTo(b)
        fun main() {
            println(compareDouble(-1.5, -2L))
            println(compareDouble(2.0, 2L))
            println(compareDouble(9007199254740992.0, 9007199254740993L))
            println(16777216f.compareTo(16777217))
            println(16777216f.compareTo(16777217L))
            println(compareFloat(16777216f, 16777217.0))
            println(16777217.0.compareTo(16777216f))
            println(Double.NaN.compareTo(2))
            println(Float.NaN.compareTo(Double.NaN))
            println(Float.POSITIVE_INFINITY.compareTo(Long.MAX_VALUE))
            println(Double.NEGATIVE_INFINITY.compareTo(Long.MIN_VALUE))
            println((-0.0).compareTo(0))
            println((-0.0f).compareTo(0L))
            println((-0.0f).compareTo(0.0))
            println(0.0.compareTo(-0.0f))
        }
        """
        try assertKotlinOutput(source, moduleName: "MixedFloatingPointCompareToEdges", expected: "1\n0\n0\n0\n0\n-1\n1\n1\n0\n1\n-1\n-1\n-1\n-1\n1\n")
    }

    @Test
    func testMixedFloatingPointCompareToPreservesSafeCallEvaluation() throws {
        let source = """
        fun receiver(value: Float?): Float? {
            println("receiver")
            return value
        }
        fun argument(): Double {
            println("argument")
            return 2.0
        }
        fun main() {
            println(receiver(1.5f)?.compareTo(argument()))
            println(receiver(null)?.compareTo(argument()))
            val double: Double? = 1.5
            println(double?.compareTo(2))
            val zero: Float? = -0.0f
            println(zero?.compareTo(0.0))
            val nan: Float? = Float.NaN
            println(nan?.compareTo(Double.NaN))
            val comparator: (Float, Double) -> Int = { a, b -> a.compareTo(b) }
            println(comparator(1.5f, 2.0))
        }
        """
        try assertKotlinOutput(source, moduleName: "MixedFloatingPointCompareToSafeCall", expected: "receiver\nargument\n-1\nreceiver\nnull\n-1\n-1\n0\n-1\n")
    }

    @Test
    func testCodegenCompilesPrimitiveCompareTo() throws {
        let source = """
        fun main() {
            // Int — direct member call
            println(10.compareTo(20))
            println(20.compareTo(10))
            println(7.compareTo(7))
            // Int — inside a (Int, Int) -> Int lambda
            val cmpInt: (Int, Int) -> Int = { x, y -> x.compareTo(y) }
            println(cmpInt(30, 5))
            // Long
            println(100L.compareTo(200L))
            // Double — direct and inside a (Double, Double) -> Int lambda
            println(2.5.compareTo(1.5))
            val cmpDouble: (Double, Double) -> Int = { x, y -> x.compareTo(y) }
            println(cmpDouble(1.0, 9.0))
            // Float — direct and inside a (Float, Float) -> Int lambda
            println(2.5f.compareTo(1.5f))
            val cmpFloat: (Float, Float) -> Int = { x, y -> x.compareTo(y) }
            println(cmpFloat(1.0f, 9.0f))
            // Boolean (false < true)
            println(false.compareTo(true))
        }
        """
        try assertKotlinOutput(source, moduleName: "PrimitiveCompareTo", expected: "-1\n1\n0\n1\n-1\n1\n-1\n1\n-1\n-1\n")
    }
}
#endif
