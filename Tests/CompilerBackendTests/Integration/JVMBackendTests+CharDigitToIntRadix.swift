#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func charDigitToIntRadixMatchesKotlinStdlibAndJavaConsumers() throws {
        let runtime = try m11Runtime()
        let runtimeJars = runtime.split(separator: ":").map(String.init)
        let source = """
        fun digitValue(value: Char, radix: Int): Int = value.digitToInt(radix)

        fun printDigit(value: Char, radix: Int) {
            try {
                println(digitValue(value, radix))
            } catch (error: IllegalArgumentException) {
                println("rejected")
            }
        }

        fun main() {
            printDigit('f', 16)
            printDigit('F', 16)
            printDigit('1', 2)
            printDigit('2', 10)
            printDigit('9', 10)
            printDigit('e', 16)
            printDigit('0', 2)
            printDigit('0', 36)
            printDigit('z', 36)
            printDigit('2', 2)
            printDigit('!', 16)
            printDigit('0', 1)
            printDigit('0', 37)
        }
        """

        try withWorkspace { root in
            let result = try compile(source, root: root, mode: .jvmJar, classpath: runtimeJars)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let jar = root.appendingPathComponent("hello.jar").path
            let execution = try java(["-cp", jar + ":" + runtime, "HelloKt"])
            #expect(execution.stdout == """
            15
            15
            1
            2
            9
            14
            0
            0
            35
            rejected
            rejected
            rejected
            rejected

            """)
            #expect(execution.stderr.isEmpty)

            try """
            public final class CharDigitJavaConsumer {
                public static void main(String[] args) {
                    if (HelloKt.digitValue('f', 16) != 15) throw new AssertionError("hex digit");
                    if (HelloKt.digitValue('1', 2) != 1) throw new AssertionError("binary digit");
                    if (HelloKt.digitValue('9', 10) != 9) throw new AssertionError("decimal digit");
                    expectRejected('!', 16);
                    expectRejected('2', 2);
                    expectRejected('0', 1);
                    expectRejected('0', 37);
                    System.out.println("Java consumer passed");
                }

                private static void expectRejected(char value, int radix) {
                    try {
                        HelloKt.digitValue(value, radix);
                    } catch (IllegalArgumentException expected) {
                        return;
                    }
                    throw new AssertionError("Expected IllegalArgumentException");
                }
            }
            """.write(to: root.appendingPathComponent("CharDigitJavaConsumer.java"), atomically: true, encoding: .utf8)
            let javaCompile = try jvmTool("javac", ["-cp", jar + ":" + runtime, "CharDigitJavaConsumer.java"], root: root)
            try #require(javaCompile.exitCode == 0, "\(javaCompile.stderr)")
            let javaExecution = try java(["-cp", root.path + ":" + jar + ":" + runtime, "CharDigitJavaConsumer"])
            #expect(javaExecution.stdout == "Java consumer passed\n")
            #expect(javaExecution.stderr.isEmpty)
        }
    }
}
#endif
