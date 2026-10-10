import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func callingOtherMainAndReenteringEntryPreservesModuleState(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlinSources([
            """
            import kotlin.io.encoding.Base64
            import kotlinx.io.bytestring.*
            var calls = 0
            fun main() {
                calls++
                if (calls == 1) {
                    println(Base64.decodeToByteString("AAA=").size)
                    startuphelper.main()
                    startuphelper.main()
                    main()
                    println(Base64.decodeToByteString("AAA=").size)
                } else {
                    println("reentry:" + calls)
                }
            }
            """,
            """
            package startuphelper
            object Counter { var value = 0 }
            fun main() {
                Counter.value++
                println("helper:" + Counter.value)
            }
            """,
        ], expectedOutput: "2\nhelper:1\nhelper:2\nreentry:2\n2\n",
           moduleName: "ModuleStartupIsolation",
           allowDefaultStdlibLibrary: allowDefaultStdlibLibrary)
    }
}
