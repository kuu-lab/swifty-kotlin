#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func importedExtensionFromInheritedMultifilePartExecutes() throws {
        let own = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            @file:JvmName("BufferUuidExtensions")
            @file:JvmMultifileClass
            package kotlin.uuid

            import java.nio.ByteBuffer

            class Uuid(val mostSignificantBits: Long, val leastSignificantBits: Long)

            fun ByteBuffer.putUuid(uuid: Uuid): ByteBuffer {
                putLong(uuid.mostSignificantBits)
                putLong(uuid.leastSignificantBits)
                return this
            }
            """.write(to: root.appendingPathComponent("Uuid.kt"), atomically: true, encoding: .utf8)
            try """
            @file:JvmName("BufferUuidExtensions")
            @file:JvmMultifileClass
            package kotlin.uuid

            fun uuidSupportMarker(): Int = 1
            """.write(to: root.appendingPathComponent("UuidSupport.kt"), atomically: true, encoding: .utf8)

            let library = root.appendingPathComponent("provider.jar")
            let compiled = try jvmTool("kotlinc", ["-Xallow-kotlin-package", "Uuid.kt", "UuidSupport.kt", "-d", library.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")

            let classpath = [library.path, own.path]
            let source = """
            import kotlin.uuid.Uuid
            import kotlin.uuid.putUuid
            import java.nio.ByteBuffer

            fun main() {
                val buffer = ByteBuffer.allocate(16)
                buffer.putUuid(Uuid(7L, 9L))
                println(buffer.getLong(0))
                println(buffer.getLong(8))
            }
            """
            let result = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            #expect(result.0 == 0, "\(result.1.map(\.message))")

            let runtimeClasspath = ([root.appendingPathComponent("hello.jar").path] + classpath)
                .joined(separator: ":")
            let execution = try java(["-cp", runtimeClasspath, "HelloKt"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "7\n9\n")
        }
    }
}
#endif
