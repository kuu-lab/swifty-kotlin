import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testNamedObjectImplicitSetterAndLazyDelegateAccess(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            object Foo {
                var log = ""
                var x: Int
                    get() = 0
                    set(value) { log += "s" }
                fun writeImplicitly(): Int {
                    x = 5
                    return x
                }
            }

            object Delegated {
                val z: Int by lazy { 7 }
            }

            fun main() {
                println(Foo.writeImplicitly())
                println(Foo.log)
                println(Delegated.z)
                println(Delegated.z)
            }
            """,
            expectedOutput: "0\ns\n7\n7\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
