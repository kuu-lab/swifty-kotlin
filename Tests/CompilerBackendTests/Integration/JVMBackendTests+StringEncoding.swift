#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func stringEncodeToByteArrayMatchesOfficialStdlibAndJavaConsumer() throws {
        try withWorkspace { root in
            let runtime = try m11Runtime()
            let source = #"""
            fun encodeToBytes(value: String): ByteArray = value.encodeToByteArray()

            fun main() {
                val ascii = "ABC".encodeToByteArray()
                println("ascii:${ascii.size}:${ascii[0]},${ascii[1]},${ascii[2]}")

                val multibyte = "éあ😀".encodeToByteArray()
                println("multibyte:${multibyte.size}:${multibyte[0]},${multibyte[1]},${multibyte[2]},${multibyte[3]},${multibyte[4]},${multibyte[5]},${multibyte[6]},${multibyte[7]},${multibyte[8]}")
                println("empty:${"".encodeToByteArray().size}")

                val range = "AéあZ".encodeToByteArray(1, 3)
                println("range:${range.size}:${range[0]},${range[1]},${range[2]},${range[3]},${range[4]}")
                println("emptyRange:${"abc".encodeToByteArray(2, 2).size}")

                val defaultStart = "ABC".encodeToByteArray(startIndex = 1)
                println("defaultStart:${defaultStart.size}:${defaultStart[0]},${defaultStart[1]}")
                val defaultEnd = "ABC".encodeToByteArray(endIndex = 2)
                println("defaultEnd:${defaultEnd.size}:${defaultEnd[0]},${defaultEnd[1]}")

                val malformed = "\uD800"
                val replacement = malformed.encodeToByteArray(throwOnInvalidSequence = false)
                println("replacement:${replacement.size}:${replacement[0]}")
                try {
                    malformed.encodeToByteArray(throwOnInvalidSequence = true)
                    println("invalidUtf16:accepted")
                } catch (error: Exception) {
                    println("invalidUtf16:rejected")
                }

                try {
                    "abc".encodeToByteArray(-1)
                    println("negativeStart:accepted")
                } catch (error: IndexOutOfBoundsException) {
                    println("negativeStart:index")
                }
                try {
                    "abc".encodeToByteArray(0, 4)
                    println("largeEnd:accepted")
                } catch (error: IndexOutOfBoundsException) {
                    println("largeEnd:index")
                }
                try {
                    "abc".encodeToByteArray(2, 1)
                    println("reversed:accepted")
                } catch (error: IllegalArgumentException) {
                    println("reversed:argument")
                }
            }
            """#
            let classpath = runtime.components(separatedBy: ":")
            let compiled = try compile(source, root: root, mode: .jvmJar, classpath: classpath)
            try #require(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let application = root.appendingPathComponent("hello.jar").path
            let generated = try java(["-cp", application + ":" + runtime, "HelloKt"])
            #expect(generated.exitCode == 0, "\(generated.stderr)")
            #expect(generated.stderr.isEmpty)

            _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "reference.jar"], root: root)
            let reference = try java(["-cp", root.appendingPathComponent("reference.jar").path + ":" + runtime, "HelloKt"])
            #expect(reference.exitCode == 0, "\(reference.stderr)")
            #expect(reference.stdout == generated.stdout)
            #expect(generated.stdout == """
            ascii:3:65,66,67
            multibyte:9:-61,-87,-29,-127,-126,-16,-97,-104,-128
            empty:0
            range:5:-61,-87,-29,-127,-126
            emptyRange:0
            defaultStart:2:66,67
            defaultEnd:2:65,66
            replacement:1:63
            invalidUtf16:rejected
            negativeStart:index
            largeEnd:index
            reversed:argument

            """)

            let consumer = root.appendingPathComponent("EncodeByteArrayConsumer.java")
            try """
            public final class EncodeByteArrayConsumer {
                public static void main(String[] args) {
                    byte[] encoded = HelloKt.encodeToBytes("あ");
                    if (encoded.length != 3 || encoded[0] != (byte) 0xE3 ||
                        encoded[1] != (byte) 0x81 || encoded[2] != (byte) 0x82) {
                        throw new AssertionError(java.util.Arrays.toString(encoded));
                    }
                    System.out.println("java:" + encoded.length + ":" + encoded[0] + "," + encoded[1] + "," + encoded[2]);
                }
            }
            """.write(to: consumer, atomically: true, encoding: .utf8)
            let javacResult = try javac(["-cp", application + ":" + runtime, "-d", root.path, consumer.path])
            #expect(javacResult.exitCode == 0, "\(javacResult.stderr)")
            let javaConsumer = try java(["-cp", application + ":" + runtime + ":" + root.path, "EncodeByteArrayConsumer"])
            #expect(javaConsumer.exitCode == 0, "\(javaConsumer.stderr)")
            #expect(javaConsumer.stdout == "java:3:-29,-127,-126\n")
            #expect(javaConsumer.stderr.isEmpty)
        }
    }
}
#endif
