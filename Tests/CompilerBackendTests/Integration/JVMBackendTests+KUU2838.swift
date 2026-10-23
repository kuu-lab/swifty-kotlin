#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu2838JvmStdlibTripleAndToList(mode: EmitMode) throws {
        let runtime = try m11Runtime()
        let stdlib = try #require(runtime.split(separator: ":").first.map(String.init))
        let tuplesSource = String(decoding: try JVMStdlibCatalog.read("kotlin/Tuples.kt"), as: UTF8.self)
        let tripleStart = try #require(tuplesSource.range(of: "public data class Triple")?.lowerBound)
        let tripleEnd = try #require(tuplesSource.range(of: "\npublic infix fun", range: tripleStart ..< tuplesSource.endIndex)?.lowerBound)
        let tripleDeclaration = String(tuplesSource[tripleStart ..< tripleEnd])

        try withWorkspace { root in
            // Compile the bundled declaration in isolation; full stdlib jar generation is tracked separately in KUU-3046.
            let source = """
                package kotlin

                \(tripleDeclaration)

                fun main() {
                    val triple = Triple(1, "a", 2.0)
                    if (triple.third != 2.0) throw IllegalStateException("third")
                    if (triple.toList().toString() != "[1, a, 2.0]") throw IllegalStateException("toList")
                    if (triple.toString() != "(1, a, 2.0)") throw IllegalStateException("toString")
                    if (triple.copy(third = 3.0).toString() != "(1, a, 3.0)") throw IllegalStateException("copy")
                }
                """
            let compiled = try compile(source, root: root, mode: mode, classpath: [stdlib])
            try #require(compiled.0 == 0, "Triple compilation failed: \(compiled.1.map(\.message))")

            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + runtime, "kotlin.HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout.isEmpty)
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
