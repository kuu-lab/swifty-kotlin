#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func unsignedStringsLinkAndPreserveRadixAndOverflowRules() throws {
        let own = try ownStdlibLibrary()
        let official = try m11Runtime()
        try withWorkspace { root in
            let file = "UnsignedStringsProbe.kt"
            let source = """
            fun main() {
                println("+ff".toUInt(16).toString(16))
                println("4294967295".toUInt().toString(16))
                println("18446744073709551615".toULong().toString(16))
                println("1111111111111111111111111111111111111111111111111111111111111111".toULong(2).toString(16))
                println("١٥".toUInt().toString(16))
                println("255".toUByte().toString(16))
                println("65535".toUShort().toString(16))
                println("18446744073709551616".toULongOrNull() == null)
                println("4294967296".toUIntOrNull() == null)
                println("256".toUByteOrNull() == null)
                println("65536".toUShortOrNull() == null)
                println("-1".toUIntOrNull(16) == null)
                println(" 0".toULongOrNull() == null)
                try {
                    "z".toUInt(16)
                } catch (_: NumberFormatException) {
                    println("invalid number")
                }
                try {
                    "1".toULongOrNull(1)
                } catch (_: IllegalArgumentException) {
                    println("invalid radix")
                }
            }
            """
            try source.write(to: root.appendingPathComponent(file), atomically: true, encoding: .utf8)
            let artifact = root.appendingPathComponent("probe.jar")
            let compiled = try jvmTool("kotlinc", [file, "-d", artifact.path], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let reference = try java(["-Xverify:all", "-cp", artifact.path + ":" + official, "UnsignedStringsProbeKt"])
            try #require(reference.exitCode == 0, "\(reference.stderr)")
            let precompiled = try java(["-Xverify:all", "-cp", artifact.path + ":" + own.path, "UnsignedStringsProbeKt"])
            #expect(precompiled.exitCode == 0, "\(precompiled.stderr)")
            #expect(precompiled.stdout == reference.stdout)

            let (app, exit, diagnostics) = try m22Build(root: root, sources: [(file, source)], name: "candidate.jar", classpath: [own.path])
            try #require(exit == 0, "\(diagnostics.map(\.message))")
            let candidate = try java(["-Xverify:all", "-cp", app.path + ":" + own.path, "UnsignedStringsProbeKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif
