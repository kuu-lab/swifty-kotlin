#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func multipleWhereUpperBoundsCompileAndRejectOutOfBoundArguments() throws {
        try withWorkspace { root in
            let validSource = """
            fun <T> size(value: T): Int where T : CharSequence, T : Comparable<T> = value.length + value.compareTo(value)
            fun main() { println(size("hello")) }
            """
            try runM11(validSource, expected: "5\n", mode: .jvmJar, root: root)

            let runtime = try m11Runtime()
            let output = root.appendingPathComponent("hello.jar")
            let bytecode = try jvmTool("javap", ["-v", "-p", "-classpath", output.path, "HelloKt"], root: root)
            #expect(bytecode.stdout.contains("<T::Ljava/lang/CharSequence;:Ljava/lang/Comparable<TT;>;>(TT;)I"))
            let previousOutput = try Data(contentsOf: output)
            let invalidSource = """
            fun <T> size(value: T): Int where T : CharSequence, T : Comparable<T> = value.length + value.compareTo(value)
            fun main() { println(size(42)) }
            """
            let invalid = try compile(invalidSource, root: root, mode: .jvmJar)
            #expect(invalid.0 == 1, "\(invalid.1.map(\.message))")
            #expect(!invalid.1.contains { $0.code == "KSWIFTK-JVM-0001" })
            #expect(!invalid.1.contains { $0.code.hasPrefix("KSWIFTK-ICE") })
            #expect(try Data(contentsOf: output) == previousOutput)

            do {
                _ = try jvmTool("kotlinc", ["hello.kt", "-cp", runtime, "-d", "invalid.jar"], root: root)
                Issue.record("kotlinc accepted an argument that does not satisfy the where bounds")
            } catch CommandRunnerError.nonZeroExit(let error) {
                #expect(error.stderr.contains("argument type mismatch"), "\(error.stderr)")
            }
        }
    }
}
#endif
