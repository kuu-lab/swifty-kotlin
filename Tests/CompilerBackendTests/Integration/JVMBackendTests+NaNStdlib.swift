#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func ownStdlibNaNPredicates(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            fun main() {
                println((0.0 / 0.0).isNaN())
                println((0.0f / 0.0f).isNaN())
                println((1.0 / 0.0).isNaN())
                println((-1.0f / 0.0f).isNaN())
                println(0.0.isNaN())
                println((-0.0f).isNaN())
                println(Double.NaN.isNaN())
                println(Float.Companion.NaN.isNaN())
                println(Double.POSITIVE_INFINITY)
                println(Float.NEGATIVE_INFINITY)
                println(Double.MIN_VALUE > 0.0)
                println(Float.MIN_VALUE > 0.0f)
                println(Double.MAX_VALUE > Double.MIN_VALUE)
                println(Float.MAX_VALUE > Float.MIN_VALUE)
                println(Double.SIZE_BITS)
                println(Float.SIZE_BYTES)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "true\ntrue\nfalse\nfalse\nfalse\nfalse\ntrue\ntrue\nInfinity\n-Infinity\ntrue\ntrue\ntrue\ntrue\n64\n4\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
