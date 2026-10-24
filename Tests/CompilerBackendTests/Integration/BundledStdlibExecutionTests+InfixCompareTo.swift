import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testUnsignedInfixCompareTo(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        fun compareUInts(a: UInt, b: UInt) = a compareTo b
        fun compareULongs(a: ULong, b: ULong) = a compareTo b

        fun box(): String {
            if (compareUInts(0u, 1u) != -1) return "Fail 1"
            if (compareULongs(0u, 1u) != -1) return "Fail 2"
            return "OK"
        }

        fun main() {
            println(0u compareTo 1u)
            println(0uL compareTo 1uL)
            println(box())
        }
        """

        for optLevel in [OptimizationLevel.O0, .O2] {
            try compileAndRunKotlin(
                source,
                expectedOutput: "-1\n-1\nOK\n",
                moduleName: "KUU2320InfixCompareToO\(optLevel.rawValue)",
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
                optLevel: optLevel
            )
        }
    }

    // KUU-3143: `kotlin.UInt`/`ULong`/`UByte`/`UShort` FQ names collide with the
    // bundled `fun UInt(data: Int)`-style constructor helpers, so a member
    // lookup that follows the first symbol at the FQ name can root at the
    // function instead of the primitive class. Member `compareTo` calls and
    // `UIntArray.max()` must still resolve and run on the precompiled stdlib
    // artifact path as well as the bundled-source path.
    @Test(arguments: [true, false])
    func testUnsignedMemberCompareToAndUIntArrayMax(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        @OptIn(ExperimentalUnsignedTypes::class)
        fun main() {
            println(1u.compareTo(2u))
            println(1uL.compareTo(2uL))
            println(1.toUByte().compareTo(2.toUByte()))
            println(1.toUShort().compareTo(2.toUShort()))
            println(1u < 2u)
            println(uintArrayOf(1u, 2u).max())
            println(uintArrayOf(1u, 2u).min())
        }
        """

        for optLevel in [OptimizationLevel.O0, .O2] {
            try compileAndRunKotlin(
                source,
                expectedOutput: "-1\n-1\n-1\n-1\ntrue\n2\n1\n",
                moduleName: "KUU3143UnsignedMemberCompareToO\(optLevel.rawValue)",
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
                optLevel: optLevel
            )
        }
    }
}
