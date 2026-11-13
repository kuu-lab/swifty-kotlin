#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func referenceArrayAsIterableUsesRepositoryStdlib(mode: EmitMode) throws {
        try repositoryStdlibRuntimeRegression(name: "referenceArrayAsIterable", mode: mode)
    }

    @Test
    func referenceArrayAsIterableRunsOfficialKotlinConsumer() throws {
        try officialKotlinRuntimeRegression(name: "referenceArrayAsIterable")
    }
}
#endif
