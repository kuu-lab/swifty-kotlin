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
}
