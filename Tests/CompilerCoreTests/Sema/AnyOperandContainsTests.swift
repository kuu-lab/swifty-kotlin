#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct AnyOperandContainsTests {
    @Test func viableContainsMemberShadowsMoreSpecificIterableExtension() throws {
        let ctx = makeContextFromSource("""
        class Bucket : Iterable<Int> {
            override fun iterator(): Iterator<Int> = listOf(1).iterator()
            operator fun contains(x: Any?): Boolean = false
        }
        fun check(values: Bucket): Boolean = 1 in values
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var membershipCount = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard case .inExpr = ast.arena.expr(id),
                  let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user
            else { continue }
            let binding = try #require(sema.bindings.callBinding(for: id))
            let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["Bucket", "contains"])
            membershipCount += 1
        }
        #expect(membershipCount == 1)
    }

    @Test func inapplicableUserExtensionDoesNotHideIterableContains() throws {
        let ctx = makeContextFromSource("""
        operator fun IntRange.contains(x: String): Boolean = true
        fun check(x: Any?) {
            x in 1..3
            x !in 1..3
            (1..3).contains(x)
            x in 1L..3L
            x in 'a'..'c'
            when (x) { in 1..3 -> true; else -> false }
            "custom" in 1..3
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func sameElementRangeAndPrimitiveArrayMembershipRetainsScalarPaths() throws {
        let ctx = makeContextFromSource("""
        fun check(value: Char, chars: CharArray, range: CharRange) {
            value in chars
            value in range
            value in 'a'..'z'
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test func anyOperandsResolveIterableContains() throws {
        let ctx = makeContextFromSource("""
        fun check(x: Any, nullable: Any?, range: IntRange, values: Iterable<Int>) {
            x in 1..3
            x !in range
            nullable in range
            range.contains(x)
            x in values
            values.contains(x)
            when (x) {
                in 1..3 -> true
                else -> false
            }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        var containsBindings = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(id),
                  ctx.sourceManager.origin(of: range.start.file) == .user,
                  let binding = sema.bindings.callBinding(for: id),
                  let symbol = sema.symbols.symbol(binding.chosenCallee),
                  symbol.name == KnownCompilerNames(interner: ctx.interner).contains
            else { continue }
            #expect(symbol.fqName.map(ctx.interner.resolve) == ["kotlin", "collections", "contains"])
            #expect(sema.symbols.isSourceBackedSymbol(symbol.id))
            #expect(binding.substitutedTypeArguments.count == 1)
            containsBindings += 1
        }
        #expect(containsBindings == 7)
    }

    @Test func unrelatedStaticOperandTypesRemainRejected() throws {
        for source in [
            "fun bad(x: String): Boolean = x in 1..3",
            "fun bad(x: String?): Boolean = x in 1..3",
            "fun bad(x: String, values: Iterable<Int>): Boolean = x in values",
            "fun bad(x: String, values: Iterable<Int>): Boolean = values.contains(x)",
            "fun bad(x: String, values: List<Int>): Boolean = values.contains(x)",
            "fun bad(x: String): Boolean = x in listOf(1, 2, 3)",
            "fun bad(x: String): Boolean = when (x) { in 1..3 -> true; else -> false }"
        ] {
            let ctx = makeContextFromSource(source)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "\(source)")
        }
    }
}
#endif
