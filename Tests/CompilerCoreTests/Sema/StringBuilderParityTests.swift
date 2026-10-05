@testable import CompilerCore
import Testing

@Suite
struct StringBuilderParityTests {
    @Test
    func searchComparableAndTypedNullOverloadsResolve() throws {
        let ctx = makeContextFromSource("""
        fun <T : Comparable<T>> compare(first: T, second: T): Int = first.compareTo(second)
        fun parity(builder: StringBuilder) {
            builder.indexOf('b')
            builder.indexOf('B', startIndex = 1, ignoreCase = true)
            builder.lastIndexOf('c')
            builder.lastIndexOf('C', startIndex = 2, ignoreCase = true)
            builder.indexOf("bc")
            builder.lastIndexOf("bc", 2)
            val comparable: Comparable<StringBuilder> = builder
            comparable.compareTo(StringBuilder("xyz"))
            compare(builder, StringBuilder("xyz"))
            listOf(builder, StringBuilder("xyz")).sorted()
            builder.append(null as String?)
            builder.append(null as CharSequence?)
            builder.append(null as Any?)
            builder.append(null as CharArray?)
            builder.append(charArrayOf('x', 'y'))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func bareNullAppendIsAmbiguousWithoutBreakingNullableStringSpecificity() throws {
        let ctx = makeContextFromSource("""
        class NullableOverloads {
            fun append(value: String?): Int = 1
            fun append(value: CharSequence?): Int = 2
        }
        fun parity() {
            NullableOverloads().append(null)
            StringBuilder().append(null)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0003")
        #expect(errors.first?.message == "Ambiguous overload resolution.")
    }

    @Test
    func ambiguousMembersDoNotFallBackToApplicableExtensions() throws {
        let ctx = makeContextFromSource("""
        class NullableOverloads {
            fun accept(value: String?): Int = 1
            fun accept(value: CharArray?): Int = 2
        }
        fun NullableOverloads.accept(value: Any?): Int = 3
        fun parity() {
            NullableOverloads().accept(null)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.count == 1, "\(errors)")
        #expect(errors.first?.code == "KSWIFTK-SEMA-0003")
    }
}
