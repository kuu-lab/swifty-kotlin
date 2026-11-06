import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4213: an explicit import must outrank a same-package top-level
    /// declaration even when the call passes a lambda argument. Kotlin's
    /// candidate tower tries the explicit-import tier first, so `flow {}`
    /// binds to the imported `unsafeFlow`, not the same-package `flow`
    /// (mirrors kotlinx.coroutines Builders.kt, where the alias import of
    /// `unsafeFlow as flow` previously produced SEMA-0003 ambiguity).
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
