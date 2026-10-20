#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jdkSortProfilesPreserveGenericSAMAndExceptions(mode: EmitMode) throws {
        let library = try ownStdlibLibrary()
        try withWorkspace { root in
            let result = try compile("""
            import java.util.Arrays.sort
            import java.util.Collections
            import java.util.Comparator
            import java.security.InvalidParameterException
            data class Job(val finish: Int, val name: String)
            fun main() {
                val numbers = intArrayOf(4, -2, 4, 1)
                sort(numbers); println(numbers.joinToString())
                sort(intArrayOf())
                val jobs: List<Job> = mutableListOf(Job(2, "a"), Job(1, "b"), Job(2, "c"))
                Collections.sort(jobs, Comparator.comparingInt { x: Job -> x.finish })
                for (job in jobs) println(job.name)
                try { throw InvalidParameterException("negative") }
                catch (e: IllegalArgumentException) { println(e.message) }
                println(InvalidParameterException().message)
            }
            """, root: root, mode: mode, classpath: [library.path])
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let output = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes")
            let execution = try java(["-cp", output.path + ":" + library.path, "HelloKt"])
            #expect(execution.exitCode == 0)
            #expect(execution.stdout == "-2, 1, 4, 4\nb\na\nc\nnegative\nnull\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
