import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testNestedObjectValuesAreMaterializedForAccess(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
            import kotlin.native.runtime.GC

            fun main() {
                GC.MainThreadFinalizerProcessor.batchSize = 5uL
                println(GC.MainThreadFinalizerProcessor.batchSize)

                val processor = GC.MainThreadFinalizerProcessor
                processor.batchSize = 7uL
                println(processor.batchSize)
            }
            """,
            expectedOutput: "5\n7\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
