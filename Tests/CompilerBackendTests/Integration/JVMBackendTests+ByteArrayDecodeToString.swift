#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func byteArrayDecodeToStringUsesUtf8AndSupportsJavaConsumer() throws {
        let library = try ownStdlibRuntime()
        try withWorkspace { root in
            let source = #"""
            fun main() {
                println(byteArrayOf(65, 66).decodeToString())
                println(byteArrayOf(0xE3.toByte(), 0x81.toByte(), 0x82.toByte()).decodeToString())
                println(byteArrayOf().decodeToString())
                val malformed = byteArrayOf(0xC3.toByte(), 0x28)
                println(malformed.decodeToString())
            }
            """#
            let app = try m22Build(
                root: root,
                sources: [("main.kt", source)],
                name: "app.jar",
                classpath: [library.path]
            )
            try #require(app.1 == 0, "\(app.2.map(\.message))")

            let execution = try java(["-cp", app.0.path + ":" + library.path, "MainKt"])
            #expect(execution.stdout == "AB\nあ\n\n\u{FFFD}(\n")
            #expect(execution.stderr.isEmpty)

            let javaSource = #"""
            public class ByteArrayDecodeToStringJavaConsumer {
                public static void main(String[] args) {
                    System.out.println(kotlin.text.StringsKt.decodeToString(new byte[] {65, 66}));
                    System.out.println(kotlin.text.StringsKt.decodeToString(new byte[] {(byte) 0xC3, 0x28}));
                }
            }
            """#
            let facadeStub = #"""
            package kotlin.text;
            public final class StringsKt {
                public static String decodeToString(byte[] bytes) { throw new AssertionError(); }
            }
            """#
            let javaSourceURL = root.appendingPathComponent("ByteArrayDecodeToStringJavaConsumer.java")
            try javaSource.write(to: javaSourceURL, atomically: true, encoding: .utf8)
            let facadeStubURL = root.appendingPathComponent("StringsKt.java")
            try facadeStub.write(to: facadeStubURL, atomically: true, encoding: .utf8)
            let javaCompileRoot = root.appendingPathComponent("java-compile")
            let javaRuntimeRoot = root.appendingPathComponent("java-runtime")
            try FileManager.default.createDirectory(at: javaCompileRoot, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: javaRuntimeRoot, withIntermediateDirectories: true)
            let javaCompilation = try javac(["-d", javaCompileRoot.path, javaSourceURL.path, facadeStubURL.path])
            #expect(javaCompilation.exitCode == 0)
            let consumerClass = javaCompileRoot.appendingPathComponent("ByteArrayDecodeToStringJavaConsumer.class")
            try FileManager.default.copyItem(
                at: consumerClass,
                to: javaRuntimeRoot.appendingPathComponent("ByteArrayDecodeToStringJavaConsumer.class")
            )
            let javaConsumer = try java(["-cp", javaRuntimeRoot.path + ":" + library.path, "ByteArrayDecodeToStringJavaConsumer"])
            #expect(javaConsumer.stdout == "AB\n\u{FFFD}(\n")
            #expect(javaConsumer.stderr.isEmpty)

            let rejected = try compile(
                "fun main() { intArrayOf(65).decodeToString() }",
                root: root,
                mode: .jvmJar,
                classpath: [library.path]
            )
            #expect(rejected.0 != 0)
            #expect(rejected.1.contains { $0.severity == .error && $0.code == "KSWIFTK-SEMA-0024" })
            #expect(!rejected.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
        }
    }
}
#endif
