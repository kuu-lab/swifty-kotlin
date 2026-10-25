@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-3057: Java numeric static APIs remain usable through their wrappers
    /// without shadowing Kotlin's primitive Long and Double types.
    @Test(arguments: [false, true], [0, 2])
    func javaLangNumericWrappers(
        allowDefaultStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(Integer.parseInt("42"))
                println(Integer.parseInt("ff", 16))
                println(Integer.toHexString(-1))
                println(Integer.numberOfLeadingZeros(1))
                println(Integer.rotateLeft(1, 1))
                println(Integer.reverse(1))

                println(Long.parseLong("99"))
                println(java.lang.Long.parseLong("ff", 16))
                println(Long.toHexString(-1L))
                println(Long.numberOfLeadingZeros(1L))
                println(Long.rotateLeft(1L, 1))
                println(Long.reverse(1L))

                println(Double.parseDouble("1.5"))
                println(java.lang.Double.parseDouble("2.5"))
                println(Double.isNaN(0.0 / 0.0))
                println(java.lang.Double.isInfinite(1.0 / 0.0))
                println(Double.compare(-0.0, 0.0))
                println(Thread.currentThread() === Thread.currentThread())
            }
            """,
            expectedOutput: "42\n255\nffffffff\n31\n2\n-2147483648\n99\n255\nffffffffffffffff\n63\n2\n-9223372036854775808\n1.5\n2.5\ntrue\ntrue\n-1\ntrue\n",
            moduleName: "KUU3057JavaLangNumericWrappers",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }

    /// KUU-3445: Java wrapper shims expose primitive parsing and static APIs.
    @Test(arguments: [false, true])
    func javaLangWrapperStaticSurface(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(java.lang.Float.parseFloat("1.5"))
                println(java.lang.Float.toHexString(1.5F))
                println(java.lang.Float.toHexString(Float.MIN_VALUE))
                println(java.lang.Float.toHexString(-0.0F))

                println(java.lang.Boolean.parseBoolean("TrUe"))
                println(java.lang.Boolean.parseBoolean("yes"))
                println(java.lang.Boolean.hashCode(true))

                println(java.lang.Byte.parseByte("5"))
                println(java.lang.Byte.parseByte("7f", 16))
                println(java.lang.Byte.toUnsignedInt((-1).toByte()))

                println(java.lang.Short.parseShort("5"))
                println(java.lang.Short.parseShort("7fff", 16))
                println(java.lang.Short.toUnsignedInt((-1).toShort()))

                println(java.lang.Integer.toHexString(255))
                println(java.lang.Integer.toHexString(-1))
                println(java.lang.Integer.toUnsignedLong(-1))
                println(java.lang.Integer.hashCode(-1))
                println(java.lang.Integer.sum(20, 22))

                println(java.lang.Double.toHexString(1.5))
                println(java.lang.Double.toHexString(-0.0))
                println(java.lang.Double.hashCode(1.5))

                println(java.lang.Long.toHexString(255L))
                println(java.lang.Long.toHexString(-1L))
                println(java.lang.Long.hashCode(-1L))
            }
            """,
            expectedOutput: "1.5\n0x1.8p0\n0x0.000002p-126\n-0x0.0p0\ntrue\nfalse\n1231\n5\n127\n255\n5\n32767\n65535\nff\nffffffff\n4294967295\n-1\n42\n0x1.8p0\n-0x0.0p0\n1073217536\nff\nffffffffffffffff\n0\n",
            moduleName: "KUU3445JavaLangWrapperStaticSurface",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
