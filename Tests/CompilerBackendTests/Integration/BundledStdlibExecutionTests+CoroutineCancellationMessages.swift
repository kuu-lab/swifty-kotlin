import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testCoroutineCancellationMessagesMatchKotlin(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            diffCaseSource("kuu1425_coroutine_cancellation_messages.kt", file: #filePath),
            expectedOutput: "DeferredCoroutine was cancelled\nDeferredCoroutine was cancelled\nBlockingCoroutine is cancelling\n",
            moduleName: "KUU1425CoroutineCancellationMessages",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
