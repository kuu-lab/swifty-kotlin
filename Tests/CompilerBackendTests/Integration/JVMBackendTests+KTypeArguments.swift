#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledKTypeArgumentsReflectVarianceAndStars() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.reflect.typeOf

            class Session {
                fun data(): MutableList<out String?> = mutableListOf()
                fun unknown(): List<*> = emptyList<Any?>()
            }

            fun main() {
                println(typeOf<Session>().arguments.size)
                val members = Session::class.members
                val nested = members.first { it.name == "data" }.returnType.arguments.single()
                println(nested.variance)
                println(nested.type?.isMarkedNullable)
                val star = members.first { it.name == "unknown" }.returnType.arguments.single()
                println(star.type == null && star.variance == null)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "0\nOUT\ntrue\ntrue\n")
        }
    }
}
#endif
