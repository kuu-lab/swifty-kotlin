@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CastToAnySmartCastTests {
    @Test
    func nonNullCastPreservesConcreteAndGenericTypes() throws {
        let ctx = makeContextFromSource("""
        enum class E { A, B }
        enum class F { A }
        data class Box(val value: Int)

        fun <T> requireDefinitelyNotNull(value: T & Any) = value
        fun <T> generic(value: T?): T & Any {
            value as Any
            return requireDefinitelyNotNull<T>(value)
        }

        fun comparisons(value: E?, other: E?, different: F?, number: Int?, text: String?, box: Box?) {
            val before = value == other
            val differentEnums = value == different
            value as Any
            val first = value == E.A
            val reversed = E.A == value
            val same = value == value
            val erased = value == (E.B as Any)
            number as Any
            val numeric = number == 3
            text as Any
            val textual = text == "x"
            box as Any
            val nominal = box == Box(1)
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nullableAndSafeCastsDoNotRemoveNullability() throws {
        let ctx = makeContextFromSource("""
        enum class E { A }
        fun requireEnum(value: E) {}
        fun nullableCast(value: E?) {
            value as Any?
            requireEnum(value)
        }
        fun safeCast(value: E?) {
            value as? Any
            requireEnum(value)
        }
        fun unrelated(value: E?, number: Int?) = value == number
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        let errorLines = Set(errors.compactMap { diagnostic in
            diagnostic.primaryRange.map { ctx.sourceManager.lineColumn(of: $0.start).line }
        })
        #expect(errors.count == 3, "\(errors)")
        #expect(errorLines == [5, 9, 11], "\(errors)")
        #expect(errors.allSatisfy { $0.code == "KSWIFTK-SEMA-0002" })
    }
}
