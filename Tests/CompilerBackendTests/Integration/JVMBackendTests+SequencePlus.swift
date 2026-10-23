#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func sequencePlusOverloadsCallKotlinRuntime(mode: EmitMode) throws {
        try withWorkspace { root in
            let source = #"""
            fun main() {
                val first = sequenceOf(1, 2)
                val second = sequenceOf(3)
                println((first + second).toList())
                println(first.plus(second).toList())
                println((first + listOf(4)).toList())
                println((first + arrayOf(5)).toList())
                println((first + 6).toList())
            }
            """#
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let runtime = try m11Runtime()
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == "[1, 2, 3]\n[1, 2, 3]\n[1, 2, 4]\n[1, 2, 5]\n[1, 2, 6]\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
