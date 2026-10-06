#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct WhenSubjectDeclarationTypeTests {
    @Test func nullableAnnotationControlsSubjectVariableType() throws {
        let ctx = makeContextFromSource("""
        fun classify(): String = when (val missing: Int? = null) {
            null -> "literal"
            else -> missing.toString()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let id = try #require(ast.arena.snapshot().whenSubjectTypeRefs.keys.first)
        let symbol = try #require(sema.bindings.identifierSymbols[id])
        let type = try #require(sema.symbols.propertyType(for: symbol))
        #expect(sema.types.kind(of: type) == .primitive(.int, .nullable))
    }

    @Test(arguments: [
        "when (val value: Int = null) { else -> 1 }",
        "when (val value: Int? = \"wrong\") { else -> 1 }",
        "when (val value: String = 42) { else -> 1 }",
    ])
    func rejectsIncompatibleInitializers(_ expression: String) throws {
        let ctx = makeContextFromSource("fun classify(): Int = \(expression)")
        try? runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty)
        #expect(errors.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test func exhaustivenessUsesDeclaredSubjectType() throws {
        let ctx = makeContextFromSource("""
        fun classify(): Int = when (val missing: Int? = null) {
            null -> 1
        }
        """)
        try? runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-0004" && $0.severity == .error
        })
    }

    @Test func annotationsProvideExpectedTypesAndBranchSmartCasts() throws {
        let ctx = makeContextFromSource("""
        fun nullable(value: Int?): Int = when (val item: Int? = value) {
            null -> 0
            else -> item + 1
        }
        fun widened(): Long = when (val item: Long = 42) { else -> item }
        fun generic(): Int = when (val items: List<Int> = emptyList()) { else -> items.size }
        fun callable(): Int = when (val action: (Int) -> Int = { it + 1 }) {
            is (Int) -> Int -> action(2)
            else -> 0
        }
        fun checkedGeneric(): Int = when (val items: List<Int> = emptyList()) {
            is List<*> -> items.size
            else -> -1
        }
        fun membership(): Long = when (val item: Long = 42) {
            in 40L..45L -> item
            else -> 0L
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }
}
#endif
