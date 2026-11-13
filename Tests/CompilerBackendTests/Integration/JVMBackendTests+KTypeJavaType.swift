#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func precompiledKTypeJavaTypeReturnsTheJavaClass() throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            try """
            import kotlin.reflect.javaType
            import kotlin.reflect.typeOf

            class Session

            @OptIn(ExperimentalStdlibApi::class)
            fun main() {
                println(typeOf<Session>().javaType == Session::class.java)
                println(typeOf<Int>().javaType == Int::class.java)
                println(typeOf<String>().javaType == String::class.java)
            }
            """.write(to: root.appendingPathComponent("Consumer.kt"), atomically: true, encoding: .utf8)
            let compiled = try jvmTool("kotlinc", ["Consumer.kt", "-d", "consumer.jar"], root: root)
            try #require(compiled.exitCode == 0, "\(compiled.stderr)")
            let consumer = root.appendingPathComponent("consumer.jar")
            let result = try java(["-Xverify:all", "-cp", consumer.path + ":" + library.path, "ConsumerKt"])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout == "true\ntrue\ntrue\n")
        }
    }
}
#endif
