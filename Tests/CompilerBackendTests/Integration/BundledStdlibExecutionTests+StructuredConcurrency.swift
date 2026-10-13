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

    @Test(arguments: [true, false])
    func testFailedDeferredReachesTerminalJobState(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("kuu1353_failed_deferred_job_state.kt", file: #filePath),
            expectedOutput: "ok.await=7\nok.isCompleted=true\nok.isActive=false\nok.isCancelled=false\nok.getCompleted=7\nok.ex=null\nc.await threw isCE=true\nc.isCompleted=true\nc.isActive=false\nc.isCancelled=true\nc.gc threw isCE=true\nc.ex isCE=true\nc.join-ok\nf.await threw ise=true msg=x\nf.isCompleted=true\nf.isActive=false\nf.isCancelled=true\nf.gc threw ise=true msg=x\nf.ex ise=true msg=x\nf.join threw isCE=true\ndone\nscope rethrew x\n",
            moduleName: "KUU1353FailedDeferredJobState",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
