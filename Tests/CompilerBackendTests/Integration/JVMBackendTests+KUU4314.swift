#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    /// KUU-4314: the remaining `kotlin.internal` compile-time-only annotations
    /// from the common stdlib surface must resolve on the JVM lane. They carry
    /// no runtime-visible metadata (BINARY retention at most), so emit drops
    /// them instead of requiring a classfile plan.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4314KotlinInternalAnnotationsCompileAndRun(mode: EmitMode) throws {
        let source = """
        import kotlin.internal.InlineOnly
        import kotlin.internal.KsNoInline
        import kotlin.internal.KsSymbolName
        import kotlin.internal.NonStableParameterNames
        import kotlin.internal.OnlyInputTypes

        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @InlineOnly
        inline fun inlineOnlyDoubled(x: Int): Int = x + x

        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @KsNoInline
        fun noInlineSum(a: Int, b: Int): Int = a + b

        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        @NonStableParameterNames
        fun unstableParams(a: Int, b: Int): Int = a * b

        @Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")
        fun <@OnlyInputTypes T> firstOf(x: T, y: T): T = x

        fun main() {
            println(inlineOnlyDoubled(21))
            println(noInlineSum(20, 22))
            println(unstableParams(6, 7))
            println(firstOf("a", "b"))
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            #expect(result.0 == 0, "\(result.1.map(\.message))")
            let execution = try java(mode == .jvmJar
                ? ["-jar", root.appendingPathComponent("hello.jar").path]
                : ["-cp", root.appendingPathComponent("classes").path, "HelloKt"])
            #expect(execution.stdout == "42\n42\n42\na\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
