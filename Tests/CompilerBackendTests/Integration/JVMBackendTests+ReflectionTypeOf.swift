#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledNonGenericTypeOfKeepsItsClassifier() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.reflect.KClass
            import kotlin.reflect.typeOf

            class Session

            fun main() {
                val model = typeOf<Session>()
                val text = typeOf<String>()
                println((model.classifier as KClass<*>).qualifiedName)
                println(model.isMarkedNullable)
                println(text.classifier == String::class)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "Session\nfalse\ntrue\n")
        }
    }
}
#endif
