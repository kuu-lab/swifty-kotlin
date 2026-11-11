#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func jvmFileNameAndArgumentMainPreserveLauncherArguments() throws {
        try withWorkspace { root in
            let result = try compile("""
            @file:JvmName("NamedLauncher")

            fun main(args: Array<String>) { println(args[0]); println(args.size) }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent("hello.jar")
            let archive = try ZipArchive(data: Data(contentsOf: artifact))
            #expect(archive.entries.contains { $0.name == "NamedLauncher.class" })
            let execution = try java(["-jar", artifact.path, "first", "second"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "first\n2\n")
        }
    }

    @Test
    func fileSuppressDoesNotChangeJvmFacadeIdentity() throws {
        try withWorkspace { root in
            let result = try compile("""
            @file:Suppress("UNUSED_VARIABLE")
            fun main() { println("default facade") }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent("hello.jar")
            let archive = try ZipArchive(data: Data(contentsOf: artifact))
            #expect(archive.entries.contains { $0.name == "HelloKt.class" })
            let execution = try java(["-cp", artifact.path, "HelloKt"])
            #expect(execution.stdout == "default facade\n")
            #expect(execution.stderr.isEmpty)
        }

        try withWorkspace { root in
            let result = try compile("""
            @file:kotlin.jvm.JvmName("RenamedFacade")
            @file:Suppress("UNUSED_VARIABLE")
            fun renamedFacade() { println("renamed facade") }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent("hello.jar")
            let archive = try ZipArchive(data: Data(contentsOf: artifact))
            #expect(archive.entries.contains { $0.name == "RenamedFacade.class" })
            #expect(!archive.entries.contains { $0.name == "HelloKt.class" })
        }
    }
}
#endif
