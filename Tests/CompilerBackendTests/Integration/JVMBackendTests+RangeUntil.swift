#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func intRangeUntilExpressionsMatchKotlinAndExposeJavaAbi(mode: EmitMode) throws {
        let runtime = try m11Runtime()
        try withWorkspace { root in
            let result = try compile("""
            fun intRangeUntil(): IntRange = 1..<4
            fun main() {
                println((1..<4).toList())
                println((3..<3).isEmpty())
                println((4..<3).isEmpty())
                println((Int.MIN_VALUE..<Int.MIN_VALUE + 1).toList())
                println((Int.MAX_VALUE - 1..<Int.MAX_VALUE).toList())
                println((1..<Int.MIN_VALUE).isEmpty())
                println((Int.MAX_VALUE..<Int.MAX_VALUE).isEmpty())
                println((1..3).toList())
                println((1 until 4).toList())
            }
            """, root: root, mode: mode, classpath: runtime.components(separatedBy: ":"))
            try #require(result.0 == 0, "\(result.1.map(\.message))")

            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact + ":" + runtime, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "[1, 2, 3]\ntrue\ntrue\n[-2147483648]\n[2147483646]\ntrue\ntrue\n[1, 2, 3]\n[1, 2, 3]\n")
            #expect(execution.stderr.isEmpty)

            let consumer = root.appendingPathComponent("RangeUntilConsumer.java")
            try """
            public final class RangeUntilConsumer {
                public static void main(String[] args) {
                    kotlin.ranges.IntRange range = HelloKt.intRangeUntil();
                    if (range.getStart() != 1 || range.getEndExclusive() != 4 || range.isEmpty()) {
                        throw new AssertionError(range);
                    }
                    System.out.println(range.getStart() + "..<" + range.getEndExclusive());
                }
            }
            """.write(to: consumer, atomically: true, encoding: .utf8)
            let javaCompile = try jvmTool("javac", ["-classpath", artifact + ":" + runtime, "-d", root.path, consumer.path], root: root)
            #expect(javaCompile.exitCode == 0, "\(javaCompile.stderr)")
            let javaExecution = try java(["-cp", root.path + ":" + artifact + ":" + runtime, "RangeUntilConsumer"])
            #expect(javaExecution.exitCode == 0, "\(javaExecution.stderr)")
            #expect(javaExecution.stdout == "1..<4\n")
            #expect(javaExecution.stderr.isEmpty)
        }
    }

    @Test
    func unsignedRangeUntilIsRejectedByJvmBackend() throws {
        try withWorkspace { root in
            let result = try compile("fun main() { println(1u..<4u) }", root: root, mode: .jvmJar)
            #expect(result.0 == 1)
            #expect(result.1.contains {
                $0.code == "KSWIFTK-JVM-0001"
                    && $0.message == "JVM rangeUntil expressions currently require Int operands and IntRange."
            })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))
        }
    }
}
#endif
