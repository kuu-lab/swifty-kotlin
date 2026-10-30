#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func enumComparisonOperatorsEmitEnumCompareTo() throws {
        try withWorkspace { root in
            let source = """
            enum class E { A, B, C }
            fun main() {
                println(E.A < E.B)
                println(E.B <= E.B)
                println(E.C > E.A)
                println(E.C >= E.C)
                println(E.A > E.B)
                println(E.C <= E.A)
                println(E.A.compareTo(E.C))
                println(true < false)
                println(false < true)
                println(true > false)
            }
            """
            let expected = "true\ntrue\ntrue\ntrue\nfalse\nfalse\n-2\nfalse\ntrue\ntrue\n"
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
