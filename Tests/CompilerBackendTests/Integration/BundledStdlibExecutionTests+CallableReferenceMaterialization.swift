import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func capturedExtensionFunctionReferenceMaterializesWithItsTargetName(
        allowDefaultStdlibLibrary: Bool
    ) throws {
        try compileAndRunKotlin(
            """
            fun String.tag(): String = "ext:$this"

            fun main() {
                val ref = with("s") { ::tag }
                println(ref.name)
                println(ref.call())
            }
            """,
            expectedOutput: "tag\next:s\n",
            moduleName: "KUU1433CallableReference",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
