#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func plainEnumEntriesInheritEnumCompareTo(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            enum class DeprecationLevel { WARNING, ERROR, HIDDEN }
            fun main() {
                println(DeprecationLevel.WARNING)
                println(DeprecationLevel.HIDDEN.compareTo(DeprecationLevel.WARNING))
            }
            """, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            #expect(!result.1.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" })
            let arguments = mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"]
            let execution = try java(arguments)
            #expect(execution.stdout == "WARNING\n2\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
