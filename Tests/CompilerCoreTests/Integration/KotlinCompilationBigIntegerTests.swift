#if canImport(Testing)
import Testing

@Suite struct KotlinCompilationBigIntegerTests {
    @Test func testCompile_bigIntegerAndExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val b = BigInteger("10")
            val infix = a and b
            val dotted = a.and(b)
            val text = infix.toString() + dotted.toString()
        }
        """)
    }

    // MARK: - STDLIB-GAP-PH1: bitwise and shift extension functions

    @Test func testCompile_bigIntegerOrExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val b = BigInteger("10")
            val infix = a or b
            val dotted = a.or(b)
            println(infix.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerXorExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val b = BigInteger("10")
            val infix = a xor b
            println(infix.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerInvExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val result = a.inv()
            println(result.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerShlExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("1")
            val infix = a shl 8
            val dotted = a.shl(8)
            println(infix.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerShrExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("256")
            val infix = a shr 4
            println(infix.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerToByteArray() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("255")
            val bytes = a.toByteArray()
            println(bytes.size)
        }
        """)
    }

    @Test func testCompile_bigIntegerModInverse() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("3")
            val m = BigInteger("11")
            val inv = a.modInverse(m)
            println(inv.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerModPow() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val base = BigInteger("2")
            val exp = BigInteger("10")
            val mod = BigInteger("1000")
            val result = base.modPow(exp, mod)
            println(result.toString())
        }
        """)
    }

    // MARK: - STDLIB-NUM-129 follow-up: raw Java instance method names

    @Test func testCompile_bigIntegerNot() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val result = a.not()
            println(result.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerShiftLeft() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("1")
            val result = a.shiftLeft(8)
            println(result.toString())
        }
        """)
    }

    @Test func testCompile_bigIntegerShiftRight() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("256")
            val result = a.shiftRight(4)
            println(result.toString())
        }
        """)
    }
}
#endif
