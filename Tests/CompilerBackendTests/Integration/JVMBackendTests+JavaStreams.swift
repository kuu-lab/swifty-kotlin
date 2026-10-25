#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func collectionJavaStreamBridgeMatchesJDK(mode: EmitMode) throws {
        try withWorkspace { root in
            let result = try compile("""
            import java.util.ArrayList
            import java.util.stream.Collectors
            import java.util.stream.IntStream
            import java.util.stream.StreamSupport

            fun main() {
                val mutableValues = ArrayList<Int>()
                mutableValues.add(1)
                mutableValues.add(2)
                mutableValues.add(3)
                val values: List<Int> = mutableValues
                println(values.stream().mapToInt { it * 2 }.sum())
                println(values.parallelStream().filter { it % 2 == 1 }.count())
                println(values.stream().collect(Collectors.toList<Int>()))
                println(StreamSupport.stream<Int>(values.spliterator(), false).count())
                println(IntStream.range(1, 4).sum())
            }
            """, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.filter { $0.severity == .error }.map(\.message))")

            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "12\n2\n[1, 2, 3]\n3\n6\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
