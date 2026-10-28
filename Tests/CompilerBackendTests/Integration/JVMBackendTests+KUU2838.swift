#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func bundledTripleIsVisibleToConsumers(mode: EmitMode) throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
                fun main() {
                    val triple = Triple(1, "a", 2.0)
                    println(triple)
                    println(triple.third)
                    println(triple.toList())
                    println(Pair(1, "a").second)
                }
                """
            let compiled = try compile(source, root: root, mode: mode, classpath: [stdlib.path])
            try #require(compiled.0 == 0, "Triple consumer failed: \(compiled.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let result = try java(["-cp", output.path + ":" + stdlib.path, "HelloKt"])
            #expect(result.exitCode == 0, Comment(rawValue: result.stderr))
            #expect(result.stdout == "(1, a, 2.0)\n2.0\n[1, a, 2.0]\na\n")
            #expect(result.stderr.isEmpty)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2838JvmStdlibTripleAndToList(mode: EmitMode) throws {
        let stdlib = try ownStdlibLibrary()

        try withWorkspace { root in
            let source = """
                fun main() {
                    val triple = Triple(1, "a", 2.0)
                    if (triple.third != 2.0) throw IllegalStateException("third")
                    if (triple.toList().toString() != "[1, a, 2.0]") throw IllegalStateException("toList")
                    if (triple.toString() != "(1, a, 2.0)") throw IllegalStateException("toString")
                    if (triple.copy(third = 3.0).toString() != "(1, a, 3.0)") throw IllegalStateException("copy")
                }
                """
            let compiled = try compile(source, root: root, mode: mode, classpath: [stdlib.path])
            try #require(compiled.0 == 0, "Triple compilation failed: \(compiled.1.map(\.message))")

            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + stdlib.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout.isEmpty)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
