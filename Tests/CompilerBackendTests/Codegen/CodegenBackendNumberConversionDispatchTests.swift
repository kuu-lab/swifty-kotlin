#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendNumberConversionDispatchTests {

    @Test
    func testBoxedLongToULongPreservesUnsignedEquality() throws {
        let source = """
        fun main() {
            val zero: Any = 0L
            val two: Any = 2L
            val negative: Any = -1L
            val minimum: Any = Long.MIN_VALUE
            println((zero as Long).toULong() == 0uL)
            println((two as Long).toULong() == 2uL)
            println((negative as Long).toULong() == ULong.MAX_VALUE)
            println((minimum as Long).toULong() == 9223372036854775808uL)
            val nullable: Long? = 2L
            println(nullable?.toULong() == 2uL)
        }
        """
        try assertKotlinOutput(
            source, moduleName: "BoxedLongToULongEquality",
            expected: "true\ntrue\ntrue\ntrue\ntrue\n"
        )
    }

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

    @Test
    func testNullableGenericNumberSafeCallHandlesNullAndBoxedPrimitive() throws {
        let source = """
        fun <T : Number?> convert(value: T): Int? = value?.toInt()
        fun <T : Number?> convertAfterNullCheck(value: T): Int? =
            if (value == null) null else value.toInt()

        fun main() {
            println(convert<Int?>(null))
            println(convert<Int?>(42))
            println(convertAfterNullCheck<Int?>(null))
            println(convertAfterNullCheck<Int?>(42))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "NullableGenericNumberSafeCall",
            expected: "null\n42\nnull\n42\n"
        )
    }
}
#endif
