#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledArrayIteratorUsesOwnStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            let source = """
            fun main() {
                val source = arrayOf<String?>("first", null)
                val iterator = source.iterator()
                source[0] = "updated"
                println(iterator.hasNext())
                println(iterator.next())
                println(iterator.next())
                println(iterator.hasNext())
                repeat(2) {
                    try {
                        iterator.next()
                    } catch (error: NoSuchElementException) {
                        println(error.javaClass.simpleName)
                    }
                }
                println(emptyArray<String>().iterator().hasNext())
            }
            """
            try source.write(to: root.appendingPathComponent("Probe.kt"), atomically: true, encoding: .utf8)
            let app = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", ["Probe.kt", "-d", app.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let bytecode = try javap(["-c", "-cp", app.path, "ProbeKt"])
            #expect(bytecode.stdout.contains("kotlin/jvm/internal/ArrayIteratorKt.iterator"))
            let official = try java(["-cp", app.path + ":" + m11Runtime(), "ProbeKt"])
            let candidate = try java(["-cp", app.path + ":" + stdlib.path, "ProbeKt"])
            #expect(candidate.stdout == "true\nupdated\nnull\nfalse\nNoSuchElementException\nNoSuchElementException\nfalse\n")
            #expect(candidate.stdout == official.stdout)
        }
    }
}
#endif
