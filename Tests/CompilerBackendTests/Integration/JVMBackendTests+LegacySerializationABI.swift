#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func legacySerializationCallsLinkWithOwnJVMStdlib() throws {
        let stdlib = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.reflect.typeOf
            import kotlin.time.Duration.Companion.milliseconds
            import kotlin.time.TimedValue

            fun main() {
                val (value, duration) = TimedValue("talk", 42.milliseconds)
                println(value + "/" + duration.inWholeMilliseconds)
                println(arrayOf("first", null, "first", "second").distinct())
                println(listOf("ab", "ac", "ba").groupingBy { it.first() }.eachCount())
                val type = typeOf<Map<String, Int?>?>()
                println(type)
                println(type.arguments.map { it.type?.isMarkedNullable })
            }
            """.write(to: root.appendingPathComponent("Main.kt"), atomically: true, encoding: .utf8)
            let producer = try jvmTool("kotlinc", ["Main.kt", "-d", "consumer.jar"], root: root)
            try #require(producer.exitCode == 0, "\(producer.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar").path
            let reference = try java(["-Xverify:all", "-cp", consumer + ":" + m11Runtime(), "MainKt"])
            let candidate = try java(["-Xverify:all", "-cp", consumer + ":" + stdlib.path, "MainKt"])
            #expect(candidate.exitCode == 0, "\(candidate.stderr)")
            #expect(reference.exitCode == 0, "\(reference.stderr)")
            #expect(candidate.stdout == reference.stdout)
        }
    }
}
#endif
