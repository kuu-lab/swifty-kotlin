import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4545: `createFailure(RuntimeException(...))` erased to `Any` crashed
    /// in `String.length` because `kk_any_member_to_string` fed the flat-ABI
    /// inherited `Throwable.toString` result through the raw string handle ABI.
    /// Source-backed throwables now use the Any-to-string registry, and the
    /// inherited `Throwable.toString` bridge calls `__kk_throwable_toString`.
    @Test
    func testCreateFailureThrowableErasedAnyToStringLength() throws {
        try compileAndRunKotlin(
            """
            @file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
            fun main() {
                val marker: Any = kotlin.createFailure(RuntimeException("boom"))
                println(marker.toString().length > 0)
            }
            """,
            expectedOutput: "true\n",
            moduleName: "KUU4545CreateFailureThrowableAnyToString"
        )
    }
}
