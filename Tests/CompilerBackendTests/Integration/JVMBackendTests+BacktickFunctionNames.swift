#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func backtickedJvmFunctionNamesPreserveTheirMethodName() throws {
        try withWorkspace { root in
            let result = try compile("""
            fun `hello world`(): Int = 42
            fun main() { println(`hello world`()) }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let jar = root.appendingPathComponent("hello.jar")
            let archive = try ZipArchive(data: Data(contentsOf: jar))
            let entry = try #require(archive.entries.first { $0.name == "HelloKt.class" })
            var reader = JVMClassReader(bytes: try archive.contents(of: entry))
            let owner = try reader.read()
            #expect(owner.methods.contains { $0.name == "hello world" && $0.descriptor == "()I" })

            let execution = try java(["-jar", jar.path])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)
        }
    }

    @Test(arguments: ["bad/name", "bad.name", "bad;name", "bad[name"])
    func rejectsBacktickedJvmFunctionNamesWithForbiddenSeparators(name: String) throws {
        try withWorkspace { root in
            let source = "fun `\(name)`(): Int = 7\nfun main() {}"
            let result = try compile(source, root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.code == "KSWIFTK-JVM-0001" })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }
}
#endif
