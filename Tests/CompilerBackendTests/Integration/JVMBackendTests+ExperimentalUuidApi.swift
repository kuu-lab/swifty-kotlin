#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func experimentalUuidApiConstructorMatchesRuntimeParity(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            import kotlin.uuid.ExperimentalUuidApi

            fun main() {
                val marker = ExperimentalUuidApi()
                println(marker is Annotation)
            }
            """, expected: "true\n", mode: mode, root: root)
        }
    }
}
#endif
