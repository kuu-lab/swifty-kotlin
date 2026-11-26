@testable import CompilerCore
import Testing

@Suite(.serialized)
struct FunInterfaceExtensionReceiverExecutionTests {
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
