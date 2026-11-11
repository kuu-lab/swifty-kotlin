#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
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

    // KUU-4531: kotlin.OptIn must allow FILE so file-level opt-in is accepted,
    // and the RequiresOptIn marker must still be emitted for the JVM classfile.
    @Test
    func fileOptInAllowsExperimentalApiWithinFile() throws {
        try withWorkspace { root in
            let result = try compile("""
            @file:OptIn(ExampleExperimental::class)

            @RequiresOptIn
            annotation class ExampleExperimental

            @ExampleExperimental
            fun checked(): Int = 42

            fun main() { println(checked()) }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar")
            let execution = try java(["-jar", jar.path])
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)

            let inspection = try javap(["-v", "-p", "-classpath", jar.path, "ExampleExperimental"])
            #expect(inspection.exitCode == 0, "\(inspection.stderr)")
            #expect(inspection.stdout.contains("kotlin.RequiresOptIn"), "\(inspection.stdout)")
        }
    }

    @Test
    func fileOptInDoesNotLeakIntoOtherFiles() throws {
        try withWorkspace { root in
            let result = try compile("""
            @file:OptIn(ExampleExperimental::class)

            @RequiresOptIn
            annotation class ExampleExperimental

            @ExampleExperimental
            fun checked(): Int = 42
            """, root: root, mode: .jvmJar, additionalSources: [("consumer.kt", """
            fun main() { println(checked()) }
            """)])
            #expect(result.0 == 1)
            #expect(result.1.contains { $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.message.contains("ExampleExperimental") }, "\(result.1.map(\.message))")
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }

    @Test
    func declarationOptInStillApplies() throws {
        try withWorkspace { root in
            let result = try compile("""
            @RequiresOptIn
            annotation class ExampleExperimental

            @ExampleExperimental
            fun checked(): Int = 42

            @OptIn(ExampleExperimental::class)
            fun main() { println(checked()) }
            """, root: root, mode: .jvmJar)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(["-jar", root.appendingPathComponent("hello.jar").path])
            #expect(execution.stdout == "42\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
