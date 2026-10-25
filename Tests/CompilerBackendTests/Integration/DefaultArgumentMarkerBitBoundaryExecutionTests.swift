import Testing

/// KUU-3231: a member default stub reads the `super.f(...)` marker in-band at
/// mask bit 30. Once a signature can hold parameter index 30 (31+ parameters),
/// an omitted argument there sets the same bit, so the stub misreads an
/// ordinary defaults call as a super call and dispatches statically instead of
/// virtually — JetBrains `inlineClasses/kt57973.kt`.
@Suite(.serialized)
struct DefaultArgumentMarkerBitBoundaryExecutionTests {
    @Test func valueClassInterfaceMethodDefaultsAcrossMarkerBit() throws {
        let parameters33 = (1 ... 33).map { "i\($0): Long = \($0)" }.joined(separator: ", ")
        let parameters32 = (1 ... 32).map { "i\($0): Long = \($0)" }.joined(separator: ", ")
        let arguments33 = (1 ... 33).map { "i\($0): Long" }.joined(separator: ", ")
        let arguments32 = (1 ... 32).map { "i\($0): Long" }.joined(separator: ", ")
        let sum33 = (1 ... 33).map { "i\($0)" }.joined(separator: " + ")
        let sum32 = (1 ... 32).map { "i\($0)" }.joined(separator: " + ")

        try compileAndRunKotlin(
            """
            interface IIC {
                fun f(\(parameters33)): Long

                fun g(\(parameters32)): Long
            }

            @JvmInline
            value class IC(val x: Long) : IIC {
                override fun f(\(arguments33)) = \(sum33)
                override fun g(\(arguments32)) = \(sum32)
            }

            fun main() {
                require(IC(2).f() == (1..33).sum().toLong()) {
                    "${IC(2).f()} != ${(1..33).sum()}"
                }
                require(IC(2).g() == (1..32).sum().toLong()) {
                    "${IC(2).g()} != ${(1..32).sum()}"
                }
                println("OK")
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3231ValueClassDefaultMaskBoundary"
        )
    }

    @Test func classInterfaceMethodDefaultsAcrossMarkerBit() throws {
        // The collision is in the mask ABI, not in value-class dispatch: an
        // ordinary class override with 31+ defaulted parameters takes the
        // same `f$default` virtual-dispatch path.
        let parameters31 = (1 ... 31).map { "i\($0): Long = \($0)" }.joined(separator: ", ")
        let arguments31 = (1 ... 31).map { "i\($0): Long" }.joined(separator: ", ")
        let sum31 = (1 ... 31).map { "i\($0)" }.joined(separator: " + ")

        try compileAndRunKotlin(
            """
            interface II31 {
                fun h(\(parameters31)): Long
            }

            class CC(val x: Long) : II31 {
                override fun h(\(arguments31)) = \(sum31)
            }

            fun main() {
                println(CC(2).h())
                println(CC(2).h(i31 = 1000))
            }
            """,
            expectedOutput: "496\n1465\n",
            moduleName: "KUU3231ClassDefaultMaskBoundary"
        )
    }
}
