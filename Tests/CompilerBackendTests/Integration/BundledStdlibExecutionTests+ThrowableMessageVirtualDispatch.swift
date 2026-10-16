import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testRuntimeThrowableMessageAndCauseVirtualDispatch(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            private inline fun invokeThrowableCallback(callback: (String) -> Unit) {
                callback("value")
            }

            fun main() {
                try {
                    throw IllegalStateException("outer", IllegalStateException("inner"))
                } catch (error: IllegalStateException) {
                    println(error.message)
                    println(error.cause?.message)
                }

                try {
                    invokeThrowableCallback { throw IllegalStateException("from callback") }
                } catch (error: IllegalStateException) {
                    println(error.message)
                }
            }
            """,
            expectedOutput: "outer\ninner\nfrom callback\n",
            moduleName: "ThrowableMessageVirtualDispatch",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
