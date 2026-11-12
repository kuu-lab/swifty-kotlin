#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func referenceArrayAsListUsesRepositoryStdlib(mode: EmitMode) throws {
        try repositoryStdlibRuntimeRegression(name: "referenceArrayAsList", mode: mode)
    }

    @Test
    func referenceArrayAsListRunsOfficialKotlinConsumer() throws {
        try officialKotlinRuntimeRegression(name: "referenceArrayAsList")
    }
}
#endif
