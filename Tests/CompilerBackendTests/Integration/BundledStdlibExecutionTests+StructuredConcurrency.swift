import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testChildFailureCancelsParentAndSiblings(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("coroutine_child_failure_propagation.kt", file: #filePath),
            expectedOutput: "await threw\nasync sibling active: false\nasync scope active: false\nasync kill\nparent cancelled\nlaunch scope active: false\nlaunch kill\njoining kill\nfirst while joining\nsupervisor kill\nsupervisor scope active: true\nsupervisor sibling completed\nnested kill\nouter scope active: true\nfirst child failure\ncleanup failure\n",
            moduleName: "KUU1338StructuredConcurrency",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
