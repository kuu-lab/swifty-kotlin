#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibMathPowers(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            import kotlin.math.pow
            fun main() {
                println(2.0.pow(3.0)); println(2.0.pow(-3))
                println(4.0f.pow(0.5f)); println(2.0f.pow(-2))
                println((-2.0).pow(3)); println((-2.0f).pow(3))
                val invalid = (-2.0).pow(0.5)
                println(invalid != invalid)
                println(1.0 / (-0.0).pow(3)); println(1.0f / (-0.0f).pow(3))
                println(0.0.pow(0)); println(1.0.pow(2147483647))
            }
            """
            let result = try compile(source, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "8.0\n0.125\n2.0\n0.25\n-8.0\n-8.0\ntrue\n-Infinity\n-Infinity\n1.0\n1.0\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
