#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct JVMSerializableBoundTests {
    @Test
    func builtinValuesSatisfySerializableBoundsAndIsChecks() throws {
        let sources = [
            """
            import java.io.Serializable

            fun <T : Serializable> keep(value: T): T = value
            fun <T> compareAndKeep(value: T): T where T : Comparable<T>, T : Serializable = value

            interface List<out E>
            fun <T> listOf(value: T): List<T> = null!!

            fun keepArray(value: Array<Int>) { keep(value) }
            fun keepIntArray(value: IntArray) { keep(value) }

            fun check() {
                5 is Serializable
                2.5 is Serializable
                "s" is Serializable
                keep(5)
                keep(2.5)
                keep("s")
                compareAndKeep(5)
                listOf(1) is Serializable
            }
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .jvmJar)
            try JVMPreparationPhase().run(ctx)
            try runSema(ctx)

            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
