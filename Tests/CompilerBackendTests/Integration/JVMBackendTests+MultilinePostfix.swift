#if canImport(Testing)
import Foundation
import Testing
@testable import CompilerCore

extension JVMBackendTests {
    @Test
    func jvmPostfixCallsPreserveMultilineStatementBoundaries() throws {
        let source = """
        class Box(var value: Int)

        fun main() {
            val box: Any = Box(1)
            println("before")
            (box as Box).value = 3
            val value = when (box.value) {
                3 -> "matched"
                else -> "different"
            }.uppercase()
            println(value)
            println(box.value == 3
                && value == "MATCHED")
            println(box.value)
        }
        """

        try withWorkspace { root in
            let compilation = try compile(source, root: root, mode: .jvmJar)
            try #require(compilation.0 == 0, Comment(rawValue: compilation.1.map(\.message).joined(separator: "\n")))
            let artifact = root.appendingPathComponent("hello.jar")
            let result = try java(["-Xverify:all", "-cp", artifact.path + ":" + m11Runtime(), "HelloKt"])
            #expect(result.stdout == "before\nMATCHED\ntrue\n3\n")
        }
    }
}
#endif
