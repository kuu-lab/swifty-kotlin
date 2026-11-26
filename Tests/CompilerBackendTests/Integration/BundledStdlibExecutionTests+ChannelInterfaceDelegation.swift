@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
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
