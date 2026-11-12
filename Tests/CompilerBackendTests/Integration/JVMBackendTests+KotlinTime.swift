#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func kotlinTimeDurationSecondsAndMeasureTimeMatchKotlinc() throws {
        try withWorkspace { root in
            try runM11("""
            import kotlin.time.Duration.Companion.seconds
            import kotlin.time.measureTime

            fun main() {
                println(3.seconds.inWholeMilliseconds)
                println((-3).seconds.inWholeMilliseconds)
                println(Long.MAX_VALUE.seconds.inWholeMilliseconds)
                println(Long.MIN_VALUE.seconds.inWholeMilliseconds)
                println(3L.seconds.inWholeSeconds)
                println(0.5.seconds.inWholeMilliseconds)
                val elapsed = measureTime {
                    var total = 0
                    repeat(10) { total += it }
                }
                println(elapsed.isNegative())
                println(elapsed.inWholeNanoseconds >= 0L)
            }
            """, expected: "3000\n-3000\n9223372036854775807\n-9223372036854775808\n3\n500\nfalse\ntrue\n", mode: .jvmJar, root: root)
        }
    }

    @Test
    func kotlinTimeDurationAbiWorksFromJavaConsumer() throws {
        try withWorkspace { root in
            let source = """
            import kotlin.jvm.JvmName
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.seconds
            import kotlin.time.measureTime

            fun durationSeconds(): Duration = 3.seconds
            @JvmName("durationMilliseconds")
            fun durationMilliseconds(value: Duration): Long = value.inWholeMilliseconds
            fun measuredTimeIsNegative(): Boolean = measureTime { }.isNegative()
            """
            let compiled = try compile(source, root: root, mode: .jvmClass)
            #expect(compiled.0 == 0, "\(compiled.1.map(\.message))")

            let runtime = try m11Runtime()
            let classes = root.appendingPathComponent("classes")
            let consumer = root.appendingPathComponent("DurationConsumer.java")
            let consumerClasses = root.appendingPathComponent("consumer")
            try FileManager.default.createDirectory(at: consumerClasses, withIntermediateDirectories: true)
            try """
            public class DurationConsumer {
                public static void main(String[] args) {
                    long duration = HelloKt.durationSeconds();
                    System.out.println(HelloKt.durationMilliseconds(duration));
                    System.out.println(HelloKt.measuredTimeIsNegative());
                }
            }
            """.write(to: consumer, atomically: true, encoding: .utf8)

            let compilation = try javac(["-cp", classes.path + ":" + runtime, "-d", consumerClasses.path, consumer.path])
            #expect(compilation.exitCode == 0, "\(compilation.stderr)")
            let execution = try java(["-cp", classes.path + ":" + consumerClasses.path + ":" + runtime, "DurationConsumer"])
            #expect(execution.exitCode == 0, "\(execution.stderr)")
            #expect(execution.stdout == "3000\nfalse\n")
        }
    }

    @Test
    func kotlinTimeSecondsRejectsUnsupportedReceiverLikeKotlinc() throws {
        try withWorkspace { root in
            let source = """
            import kotlin.time.Duration.Companion.seconds
            fun main() { println("3".seconds) }
            """
            let compiled = try compile(source, root: root, mode: .jvmJar)
            #expect(compiled.0 != 0)
            #expect(compiled.1.contains { $0.severity == .error })
            #expect(!compiled.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("hello.jar").path))

            do {
                _ = try jvmTool("kotlinc", ["hello.kt", "-cp", try m11Runtime(), "-d", "reference.jar"], root: root)
                Issue.record("kotlinc accepted an unsupported Duration receiver")
            } catch let CommandRunnerError.nonZeroExit(reference) {
                #expect(reference.exitCode != 0)
            }
        }
    }
}
#endif
