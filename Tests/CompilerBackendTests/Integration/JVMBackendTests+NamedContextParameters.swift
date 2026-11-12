#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func namedContextParametersCompileResolveAndRunOnJvm() throws {
        try withWorkspace { root in
            try runM11(
                """
                context(prefix: String)
                fun greet(): String = prefix + "!"
                fun main() { println(with("hello") { greet() }) }
                """,
                expected: "hello!\n",
                mode: .jvmJar,
                root: root
            )

            let missingContext = try compile(
                """
                context(prefix: String)
                fun greet(): String = prefix + "!"
                fun main() { println(greet()) }
                """,
                root: root,
                mode: .jvmJar
            )
            #expect(missingContext.0 != 0)
            #expect(missingContext.1.contains {
                $0.severity == .error && $0.code.hasPrefix("KSWIFTK-SEMA-")
            }, "\(missingContext.1.map(\.message))")
            #expect(!missingContext.1.contains { $0.code == "KSWIFTK-JVM-0001" })

            try runM11(
                """
                fun greet(prefix: String): String = prefix + "!"
                fun main() { println(greet("hello")) }
                """,
                expected: "hello!\n",
                mode: .jvmJar,
                root: root
            )
        }
    }
}
#endif
