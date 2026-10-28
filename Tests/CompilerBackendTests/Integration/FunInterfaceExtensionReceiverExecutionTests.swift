@testable import CompilerBackend
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite(.serialized)
struct FunInterfaceExtensionReceiverExecutionTests {
    /// KUU-3190: extension receivers must reach SAM bodies across the reported dispatch paths.
    @Test
    func receiverArgumentsReachSamImplementations() throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3190_fun_interface_receiver_dispatch.kt", file: #filePath),
            expectedOutput: "OK\nOK\nOK\nOK\n",
            moduleName: "KUU3190FunInterfaceExtensionReceiver",
            allowDefaultStdlibLibrary: true,
            expectedStderr: ""
        )
    }
}
