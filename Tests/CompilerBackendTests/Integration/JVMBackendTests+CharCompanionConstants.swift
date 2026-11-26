#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    // KUU-4702..4707: the JVM consumer contracts declared only MIN/MAX_VALUE
    // and SIZE_* on Char.Companion, so the surrogate constants were unresolved.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibCharCompanionSurrogateConstants(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                println(Char.MAX_HIGH_SURROGATE.code)
                println(Char.MAX_LOW_SURROGATE.code)
                println(Char.MAX_SURROGATE.code)
                println(Char.MAX_VALUE.code)
                println(Char.MIN_HIGH_SURROGATE.code)
                println(Char.MIN_LOW_SURROGATE.code)
                println(Char.MIN_SURROGATE.code)
                println(Char.MIN_VALUE.code)
                println(Char.SIZE_BITS)
                println(Char.SIZE_BYTES)
                val high: Char = Char.Companion.MIN_HIGH_SURROGATE
                println(high == Char.MIN_SURROGATE)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "56319\n57343\n57343\n65535\n55296\n56320\n55296\n0\n16\n2\ntrue\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
