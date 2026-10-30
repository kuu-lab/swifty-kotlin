#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func userDefinedRangeToMaterializesIntRange() throws {
        try withWorkspace { root in
            let source = """
            val topRange = 1..3
            class V(val d: Int) { operator fun rangeTo(o: V) = d..o.d }
            fun main() {
                val r = V(1)..V(3)
                for (i in r) println(i)
                for (i in V(4)..V(5)) println(i)
                println(r)
                println(r.first)
                println(2 in V(1)..V(5))
                println(9 in V(1)..V(5))
                println(topRange)
            }
            """
            let expected = "1\n2\n3\n4\n5\n1..3\n1\ntrue\nfalse\n1..3\n"
            let runtime = try m11Runtime()
            for mode in [EmitMode.jvmClass, .jvmJar] {
                let result = try compile(source, root: root, mode: mode)
                let diagnostics = result.1.map(\.message).joined(separator: "\n")
                try #require(result.0 == 0, Comment(rawValue: diagnostics))

                let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
                let execution = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
                #expect(execution.stdout == expected)
                #expect(execution.stderr.isEmpty)
            }
        }
    }
}
#endif
