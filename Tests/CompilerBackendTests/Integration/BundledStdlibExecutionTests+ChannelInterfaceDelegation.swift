@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    // Regression: interface-delegation forwarding stubs for suspend Channel.send
    // emit kk_channel_send without a trailing placeholder continuation slot, so
    // CoroutineLoweringPass must append the caller continuation instead of
    // overwriting the element argument (which failed LLVM verification at -O2).
    @Test(arguments: [false, true])
    func testChannelInterfaceDelegationO0AndO2(optimized: Bool) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kotlinx_coroutines_channel_interface_delegation.kt", file: #filePath),
            expectedOutput: """
            41
            1
            false
            true
            true
            true
            """ + "\n",
            moduleName: "ChannelInterfaceDelegation",
            allowDefaultStdlibLibrary: true,
            optLevel: optimized ? .O2 : .O0
        )
    }
}
