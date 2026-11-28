@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ArraySortByUserExtensionTests {
    @Test
    func userArraySortByExtensionTakesPrecedence() throws {
        try withTemporaryFile(contents: """
        fun Array<out Int>.sortBy(selector: (Int) -> Int?) {}
        fun probe(values: Array<out Int>) { values.sortBy { it } }
        """) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var count = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard case let .memberCall(_, name, _, _, range) = ast.arena.expr(id),
                      name == ctx.interner.intern("sortBy"),
                      ctx.sourceManager.path(of: range.start.file) == path
                else { continue }
                let binding = try #require(sema.bindings.callBinding(for: id))
                let symbol = try #require(sema.symbols.symbol(binding.chosenCallee))
                #expect(symbol.fqName.map(ctx.interner.resolve) == ["sortBy"])
                count += 1
            }
            #expect(count == 1)
        }
    }
}
