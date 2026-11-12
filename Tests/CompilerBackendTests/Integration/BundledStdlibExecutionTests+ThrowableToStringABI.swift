import Testing

extension BundledStdlibExecutionTests {
    // Regression: partitioned .kklib codegen must pass SymbolTable into
    // collectRuntimeCallbackRawABISymbols so Throwable.toString() uses the raw
    // i64 return ABI consistently across stdlib .kklib and consumer modules.
    @Test(arguments: [true, false])
    func testThrowableSubclassToStringAcrossPartitionedStdlibABI(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            class NamedThrowable(message: String?) : Throwable(message)

            class CodedException(val code: Int) : Exception() {
                override val message: String get() = "code=$code"
            }

            fun main() {
                val direct = NamedThrowable("subclass")
                println(direct.toString())
                val asAny: Any = CodedException(4)
                println(asAny.toString())
                val asThrowable: Throwable = CodedException(5)
                println(asThrowable.toString())
            }
            """,
            expectedOutput: """
            NamedThrowable: subclass
            CodedException: code=4
            CodedException: code=5
            """ + "\n",
            moduleName: "ThrowableToStringABI",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
