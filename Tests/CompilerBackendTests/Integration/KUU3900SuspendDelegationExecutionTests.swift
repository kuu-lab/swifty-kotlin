@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3900SuspendDelegationExecutionTests {
    // KUU-3900: suspend calls through `by` interface delegation must deliver
    // the delegate's result. The synthesized forwarder's merge-slot temp used
    // to carry a `.null` literal expr kind, which made flat-string call
    // marshalling substitute a null aggregate at the coroutine merge point.
    @Test(arguments: [0, 2])
    func suspendCallThroughInterfaceDelegationDeliversResult(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            try diffCaseSource("kuu_3900_suspend_by_delegation.kt", file: #filePath),
            expectedOutput: "foo delivered: false OK\nbar delivered: false SYNC\n",
            moduleName: "KUU3900SuspendByDelegation",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization))
        )
    }
}
