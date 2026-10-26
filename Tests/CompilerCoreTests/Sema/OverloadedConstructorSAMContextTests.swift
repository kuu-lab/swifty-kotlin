#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct OverloadedConstructorSAMContextTests {
    private func holderDeclaration(comparatorPrimary: Bool, capacityOverload: Bool = true) -> String {
        if comparatorPrimary {
            return """
            class Holder<T>(val ordering: Ordering<in T>?) {
                constructor(capacity: Int, ordering: Ordering<in T>?) : this(ordering)
                \(capacityOverload ? "constructor(capacity: Int) : this(null)" : "")
            }
            """
        }
        return """
        class Holder<T>(val capacity: Int, val ordering: Ordering<in T>?) {
            constructor(ordering: Ordering<in T>?) : this(11, ordering)
            \(capacityOverload ? "constructor(capacity: Int) : this(capacity, null)" : "")
        }
        """
    }

    private func check(_ body: String, comparatorPrimary: Bool, capacityOverload: Bool = true) throws -> CompilationContext {
        let ctx = makeContextFromSource("""
        fun interface Ordering<T> { fun compare(a: T, b: T): Int }
        \(holderDeclaration(comparatorPrimary: comparatorPrimary, capacityOverload: capacityOverload))
        \(body)
        """)
        try runSema(ctx)
        return ctx
    }

    @Test(arguments: [false, true])
    func nestedSamUsesExplicitOuterTypeArgument(comparatorPrimary: Bool) throws {
        let ctx = try check("""
        fun main() { Holder<Char>(Ordering { a, b -> a.code.compareTo(b.code) }) }
        """, comparatorPrimary: comparatorPrimary)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [false, true])
    func explicitNestedSamTypeArgumentStillWorks(comparatorPrimary: Bool) throws {
        let ctx = try check("""
        fun main() { Holder<Char>(Ordering<Char> { a, b -> a.code.compareTo(b.code) }) }
        """, comparatorPrimary: comparatorPrimary)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func nestedSamWithoutCapacityOverloadStillWorks() throws {
        let ctx = try check("""
        fun main() { Holder<Char>(Ordering { a, b -> a.code.compareTo(b.code) }) }
        """, comparatorPrimary: false, capacityOverload: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "Ordering<Int> { a, b -> a.compareTo(b) }",
        "Ordering { a, b -> a.code == b.code }",
    ])
    func incompatibleNestedSamStillFails(expression: String) throws {
        let ctx = try check("fun main() { Holder<Char>(\(expression)) }", comparatorPrimary: false)
        #expect(ctx.diagnostics.hasError)
    }

    @Test func sameNamedCallableKeepsItsLambdaContext() throws {
        let ctx = try check("""
        fun interface StringOrdering { fun compare(a: String, b: String): Int }
        object CharOrdering : Ordering<Char> { override fun compare(a: Char, b: Char): Int = a.code.compareTo(b.code) }
        fun Ordering(block: StringOrdering): Ordering<Char> = CharOrdering
        fun main() { Holder<Char>(Ordering { a, b -> a.length.compareTo(b.length) }) }
        """, comparatorPrimary: false)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
