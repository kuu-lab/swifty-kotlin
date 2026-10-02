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
