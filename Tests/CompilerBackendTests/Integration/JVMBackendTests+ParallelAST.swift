#if canImport(Testing)
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func parallelASTPreservesMultiFileJVMJar() throws {
        try withWorkspace { root in
            let main = """
            import sample.Greeting
            fun main() { println(Greeting.message()) }
            """
            let sources = [
                ("Greeting.kt", """
                package sample
                object Greeting {
                    fun message(): String = prefix() + "world"
                }
                """),
                ("Prefix.kt", """
                package sample
                fun prefix(): String = "hello "
                """),
            ]
            let serial = try compile(main, root: root, mode: .jvmJar, additionalSources: sources)
            try #require(serial.0 == 0, "\(serial.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar")
            let expected = try Data(contentsOf: jar)

            let parallel = try compile(
                main, root: root, mode: .jvmJar, flags: ["jobs=4"], additionalSources: sources
            )
            try #require(parallel.0 == 0, "\(parallel.1.map(\.message))")
            #expect(try Data(contentsOf: jar) == expected)
            let result = try java(["-jar", jar.path])
            #expect(result.stdout == "hello world\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
