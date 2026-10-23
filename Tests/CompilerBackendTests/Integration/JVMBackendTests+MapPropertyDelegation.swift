#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func mapPropertyDelegationUsesBundledAccessors(mode: EmitMode) throws {
        let source = """
        fun main() {
            val values = mapOf("x" to 7)
            val x: Int by values
            println(x)

            val nullableKeys = mapOf<String?, String>("name" to "Ada")
            val name: String by nullableKeys
            println(name)

            val mutableValues = mutableMapOf("count" to 1)
            var count: Int by mutableValues
            println(count)
            count = 2
            println(mutableValues["count"])
        }
        """
        try withWorkspace { root in
            let runtime = try m11Runtime()
            let result = try compile(source, root: root, mode: mode, classpath: runtime.components(separatedBy: ":"))
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-Xverify:all", "-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "7\nAda\n1\n2\n")
            #expect(execution.stderr.isEmpty)
            _ = try jvmTool("kotlinc", ["-cp", runtime, "hello.kt", "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.stdout == execution.stdout)
            #expect(reference.stderr.isEmpty)
        }
    }
}
#endif
