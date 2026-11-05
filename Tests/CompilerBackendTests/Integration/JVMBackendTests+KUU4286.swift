#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// KUU-4286: `kotlin.internal.LowPriorityInOverloadResolution` must resolve
    /// on the JVM lane so the kotlinx-datetime deprecated-ctor-shim pattern
    /// compiles. The annotation only steers overload resolution, so the emit
    /// side drops it instead of requiring a classfile plan.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4286LowPriorityCtorShimCompilesAndRuns(mode: EmitMode) throws {
        let source = """
        import kotlin.internal.LowPriorityInOverloadResolution

        class LocalDate(val year: Int, val month: Int, val day: Int)

        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @LowPriorityInOverloadResolution
        @Deprecated("shim", ReplaceWith("LocalDate(year, month, day)"), level = DeprecationLevel.WARNING)
        fun LocalDate(year: Int, monthNumber: Int, dayOfMonth: Int): LocalDate =
            LocalDate(year = year, month = monthNumber, day = dayOfMonth)

        fun main() {
            println(LocalDate(2024, 1, 15).year)
            println(LocalDate(year = 2022, monthNumber = 6, dayOfMonth = 15).year)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.stdout == "2024\n2022\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
