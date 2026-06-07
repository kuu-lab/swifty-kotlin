import XCTest

final class KotlinCompilationBigIntegerTests: XCTestCase {
    func testCompile_bigIntegerAndExtension() throws {
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

    func testCompile_bigIntegerOrExtension() throws {
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

    func testCompile_bigIntegerXorExtension() throws {
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

    func testCompile_bigIntegerInvExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("12")
            val result = a.inv()
            println(result.toString())
        }
        """)
    }

    func testCompile_bigIntegerShlExtension() throws {
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

    func testCompile_bigIntegerShrExtension() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("256")
            val infix = a shr 4
            println(infix.toString())
        }
        """)
    }

    func testCompile_bigIntegerToByteArray() throws {
        try assertKotlinCompilesToKIR("""
        import java.math.BigInteger

        fun main() {
            val a = BigInteger("255")
            val bytes = a.toByteArray()
            println(bytes.size)
        }
        """)
    }

    func testCompile_bigIntegerModInverse() throws {
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

    func testCompile_bigIntegerModPow() throws {
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
}
