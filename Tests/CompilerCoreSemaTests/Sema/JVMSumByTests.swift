#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct JVMSumByTests {

    @Test
    func sumByAndSumByDoubleResolveOnJVM() throws {
        let context = makeContextFromSource(
            """
            fun total(s: String): Int = s.sumBy { it.code }
            fun totalDouble(s: String): Double = s.sumByDouble { it.code.toDouble() / 2.0 }
            fun sequenceTotal(s: CharSequence): Int = s.sumBy { it.code }
            fun sequenceTotalDouble(s: CharSequence): Double = s.sumByDouble { it.code.toDouble() }
            fun iterableTotal(v: Iterable<Int>): Int = v.sumBy { it * it }
            fun iterableTotalDouble(v: List<Int>): Double = v.sumByDouble { it.toDouble() }
            fun sequenceSumBy(v: Sequence<Int>): Int = v.sumBy { it + 1 }
            fun sequenceSumByDouble(v: Sequence<Int>): Double = v.sumByDouble { it.toDouble() }
            """,
            emit: .jvmJar
        )
        try JVMPreparationPhase().run(context)
        try runSema(context)

        let errors = context.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "String/CharSequence/Iterable/Sequence sumBy and sumByDouble must resolve on the JVM backend: \(errors)")
    }
}
#endif
