#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func concurrentHashMapSupportsMutableMapViewsAndIndexedAccess(mode: EmitMode) throws {
        try withWorkspace { root in
            let library = try ownStdlibRuntime()
            let source = """
            import java.util.concurrent.ConcurrentHashMap

            fun main() {
                val m = ConcurrentHashMap<String, String>()
                m["empty"] = ""
                m["value"] = "x"
                val removed = m.values.removeAll { it.isEmpty() }
                m["k"] = "v"
                println(removed)
                println(m.values.size)
                println(m["empty"])
                println(m["k"])
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + library.path, "HelloKt"])
            #expect(execution.stdout == "true\n2\nnull\nv\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
