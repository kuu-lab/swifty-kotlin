import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testKUU3298TopLevelPropertyInInnerClassInitInsideObject(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            lateinit var foo: Any

            class A<T : Any> {
                inner class B(x: T) {
                    init { foo = x }
                }

                fun foo(t: T) {
                    object { val b: B = B(t) }
                }
            }

            fun main() {
                A<String>().foo("OK")
                println(foo as String)
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3298InnerClassObjectInitTopLevelProperty",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
