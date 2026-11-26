import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testExplicitImportBeatsSamePackageDeclarationWithLambda(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlinSources(
            [
                """
                package lib.internal
                fun <T> unsafeFlow(block: () -> T): T = block()
                """,
                """
                package app
                import lib.internal.unsafeFlow as flow
                fun <T> flow(block: () -> T): T = TODO("same-package declaration must not win")
                fun use(): Int = flow { 42 }
                fun main() { println(use()) }
                """,
            ],
            expectedOutput: "42\n",
            moduleName: "KUU4213ExplicitImportLambdaPriority",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
