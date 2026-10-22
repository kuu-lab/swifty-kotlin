#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionContainsAllUsesCollectionArgumentABI(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                val values: MutableList<Any> = mutableListOf("one", 2)
                println(values.containsAll(listOf<Any>("one", 2)))
                println(values.containsAll(listOf<Any>("missing")))
                println(values.containsAll(emptyList<Any>()))
                val readOnly: Collection<Int> = listOf(3, 5)
                println(readOnly.containsAll(listOf(5)))
                println(readOnly.containsAll(listOf(7)))
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\nfalse\ntrue\ntrue\nfalse\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
