#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CustomGetterTypeRegressionTests {
    @Test
    func blockGetterPreservesDeclaredPropertyTypeAtCallSite() throws {
        let ctx = makeContextFromSource("""
        class C(val p: String) {
            val c: String get() { return p }
        }
        fun main() { println(C("/a").c.length) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func blockGetterReturnTypeIsAvailableWithoutExpectedType() throws {
        let ctx = makeContextFromSource("""
        val allDone get(): Boolean { return true }
        fun inferred() = allDone
        fun negated() = !allDone
        fun stringified() = allDone.toString()
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let property = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("allDone")]))
        #expect(sema.symbols.propertyType(for: property) == sema.types.booleanType)
    }

    @Test
    func trailingLambdaGetterPreservesCallAndDeclaredPropertyType() throws {
        let ctx = makeContextFromSource("""
        class C(private val p: String) {
            val c: List<String> get() = p.split("/").filter { it.isNotEmpty() }
        }
        fun main() { println(C("/a/b").c.size) }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.isEmpty, "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
