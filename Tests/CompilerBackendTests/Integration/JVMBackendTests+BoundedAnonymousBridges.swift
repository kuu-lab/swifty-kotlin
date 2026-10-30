#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func boundedAnonymousOverridesExposeErasedBridges(mode: EmitMode) throws {
        try assertJVM(
            try diffCaseSource("jvm_bounded_comparator_bridge.kt", file: #filePath),
            "1\n3\ncomparator cast\nmeasure cast\n",
            mode: mode
        )
    }
}
#endif
