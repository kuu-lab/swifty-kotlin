import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testRuntimeThrowableMessageAndCauseVirtualDispatch(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                try {
                    throw IllegalStateException("outer", IllegalStateException("inner"))
                } catch (error: IllegalStateException) {
                    println(error.message)
                    println(error.cause?.message)
                }
            }
            """,
            expectedOutput: "outer\ninner\n",
            moduleName: "ThrowableMessageVirtualDispatch",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
