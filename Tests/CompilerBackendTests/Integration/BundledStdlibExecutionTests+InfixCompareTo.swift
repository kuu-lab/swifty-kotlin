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
}
