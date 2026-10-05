import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testSelectReadyClausesPreserveRegistrationOrder() throws {
        try compileAndRunKotlin(
            diffCaseSource("kotlinx_coroutines_select_ready.kt"),
            expectedOutput: "first:10\n20\ntimeout\nsent\n30\nclosed\ndone\n"
        )
    }

    @Test
    func testSelectWaitsAndAdaptsSuspendCallbacks() throws {
        try compileAndRunKotlin(
            diffCaseSource("kotlinx_coroutines_select_wait.kt"),
            expectedOutput: "received:7\njoined\nawaited:42\nlocked\ntrue\ntimeout\nvalue!\nlazy:9\nproperty:clause\ncaught\nsuspended\ndone\n"
        )
    }
}
