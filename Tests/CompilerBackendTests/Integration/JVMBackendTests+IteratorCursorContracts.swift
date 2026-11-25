#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func iteratorCursorContractsUseRepositoryStdlib(mode: EmitMode) throws {
        try repositoryStdlibRuntimeRegression(name: "iteratorForUsesCursor", mode: mode)
    }
}
#endif
