#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    // Keep the own-runtime cursor boundary selectable without the full profile.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func iteratorCursorContractsUseRepositoryStdlib(mode: EmitMode) throws {
        try repositoryStdlibRuntimeRegression(name: "iteratorForUsesCursor", mode: mode)
    }
}
#endif
