#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test
    func javaLongConstantsPreserveMinimumValueAndType() throws {
        try withWorkspace { root in
            let javaSource = """
                package dep;
                public class RowIds {
                    public static final long INVALID = Long.MIN_VALUE;
                    public static final long FIRST = 1L;
                }
                """
            try javaSource.write(to: root.appendingPathComponent("RowIds.java"), atomically: true, encoding: .utf8)
            _ = try jvmTool("javac", ["--release", "8", "-d", "deps", "RowIds.java"], root: root)
            let source = """
                import dep.RowIds

                const val invalid: Long = RowIds.INVALID
                const val first: Long = RowIds.FIRST

                fun main() {
                    println(invalid)
                    println(first)
                    println(RowIds.INVALID)
                    println(RowIds.FIRST)
                }
                """
            let dependencies = root.appendingPathComponent("deps").path
            let (exitCode, diagnostics) = try compile(source, root: root, mode: .jvmJar, classpath: [dependencies])
            try #require(exitCode == 0, "\(diagnostics.map(\.message))")
            let result = try java(["-jar", root.appendingPathComponent("hello.jar").path])
            #expect(result.stdout == "-9223372036854775808\n1\n-9223372036854775808\n1\n")
        }
    }
}
#endif
