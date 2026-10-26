@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct ArrayFillRangeTests {
    private func context(_ source: String, useStdlibLibrary: Bool) -> CompilationContext {
        if useStdlibLibrary { TestStdlibCache.shared.prepare() }
        return makeContextFromSource(
            source,
            emit: useStdlibLibrary ? .executable : .kirDump,
            allowDefaultStdlibLibrary: useStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func rangeDefaultsAndProjectionBoundaries(useStdlibLibrary: Bool) throws {
        // Share one source compilation across accepted and rejected calls;
        // diagnostics must be confined to the five invalid declarations.
        let ctx = context("""
        fun clear(xs: Array<Any?>) { xs.fill(null, 1, 2) }
        fun defaults(xs: Array<String>) {
            xs.fill("x")
            xs.fill(element = "x", toIndex = 1)
            xs.fill("x", fromIndex = 1)
            xs.fill(toIndex = 2, element = "x", fromIndex = 1)
        }
        fun main() {}
        fun badElement(xs: Array<String>) { xs.fill(1, 0, 1) }
        fun badProjection(xs: Array<out String>) { xs.fill("x", 0, 1) }
        fun badStar(xs: Array<*>) { xs.fill(null, 0, 1) }
        fun badDefault(xs: Array<out String>) { xs.fill("x") }
        fun badNullable(xs: Array<out String?>) { xs.fill(null, 0, 1) }
        """, useStdlibLibrary: useStdlibLibrary)
        try runSema(ctx)
        let errorLines = Set(ctx.diagnostics.diagnostics.compactMap { diagnostic -> Int? in
            guard diagnostic.severity == .error, let range = diagnostic.primaryRange else { return nil }
            return ctx.sourceManager.lineColumn(of: range.start).line
        })
        #expect(errorLines == [9, 10, 11, 12, 13])
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = memberCallExprIDs(named: "fill", in: ast, interner: ctx.interner)
            .filter {
                guard isUserSourceExpr($0, in: ctx), let range = ast.arena.exprRange($0) else { return false }
                return ctx.sourceManager.lineColumn(of: range.start).line < 9
            }
        #expect(calls.count == 5)
        for call in calls {
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(sema.symbols.isSourceBackedSymbol(binding.chosenCallee))
            let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
            #expect(signature.returnType == sema.types.unitType)
            #expect(signature.valueParameterSymbols.compactMap {
                sema.symbols.symbol($0).map { ctx.interner.resolve($0.name) }
            } == ["element", "fromIndex", "toIndex"])
        }
    }

    @Test
    func userExtensionOnProjectedArrayKeepsPriority() throws {
        let source = """
        fun Array<out String>.fill(element: String, fromIndex: Int, toIndex: Int): String = "user"
        fun main() {
            val xs: Array<out String> = arrayOf("a")
            val result: String = xs.fill("x", 0, 1)
        }
        """
        for prefix in ["", "package kotlin.collections\n"] {
            let ctx = context(prefix + source, useStdlibLibrary: true)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
        }
    }
}
