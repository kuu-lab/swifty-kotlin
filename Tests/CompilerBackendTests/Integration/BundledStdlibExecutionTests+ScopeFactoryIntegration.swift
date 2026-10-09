import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func testScopeFactoryAsyncAndParentJobIntegration(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("kotlinx_coroutines_scope_factory_async.kt"),
            expectedOutput: "false\ntrue\n1\ntrue\ntrue\n42\n43\ncancelled\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\ntrue\n44\nfalse\nruntime cancelled\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
