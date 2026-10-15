import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testCallByAcceptsArraysAllocatedByToTypedArray() throws {
        try assertKotlinOutput(
            """
            fun sourceWords(vararg words: String): Array<out String> = words

            fun main() {
                val reference = ::sourceWords
                val parameter = reference.parameters[0]
                val emptyArray = emptyList<String>().toTypedArray()
                val populatedArray = listOf("typed").toTypedArray()
                println("empty:" + reference.callBy(mapOf(parameter to emptyArray)).size)
                println("populated:" + reference.callBy(mapOf(parameter to populatedArray)).joinToString())
            }
            """,
            moduleName: "CallByToTypedArrayComponentMetadata",
            expected: "empty:0\npopulated:typed\n"
        )
    }
}
