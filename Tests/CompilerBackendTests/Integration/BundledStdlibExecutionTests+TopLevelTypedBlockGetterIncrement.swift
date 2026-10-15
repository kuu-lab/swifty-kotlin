import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testTopLevelTypedBlockGetterIncrementEvaluatesReceiverOnce(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            var holder = ""

            var globalA: A = A(-1)
                get(): A {
                    holder += "getA"
                    return field
                }

            class A(val p: Int) {
                var prop = this

                operator fun inc(): A {
                    return A(p + 1)
                }
            }

            fun box(): String {
                var a = A(1)
                ++a
                if (a.p != 2) return "fail 1: ${a.p} $holder"

                globalA = A(1)
                ++(globalA.prop)

                val holderValue = holder
                if (globalA.p != 1 || globalA.prop.p != 2 || holderValue != "getA") {
                    return "fail 2: ${globalA.p} ${globalA.prop.p} $holderValue"
                }
                return "OK"
            }

            fun main() {
                println(box())
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU2390TypedGetterIncrement",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test
    func testTopLevelTypedBlockGetterIncrementAtO2() throws {
        try compileAndRunKotlin(
            """
            var holder = ""

            var globalA: A = A(-1)
                get(): A {
                    holder += "getA"
                    return field
                }

            class A(val p: Int) {
                var prop = this
                operator fun inc(): A = A(p + 1)
            }

            fun box(): String {
                globalA = A(1)
                ++(globalA.prop)
                return if (holder == "getA" && globalA.prop.p == 2) "OK" else "FAIL:$holder"
            }

            fun main() { println(box()) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU2390TypedGetterIncrementO2",
            optLevel: .O2
        )
    }
}
