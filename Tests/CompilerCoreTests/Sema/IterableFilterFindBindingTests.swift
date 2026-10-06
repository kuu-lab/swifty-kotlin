@testable import CompilerCore
import Testing

@Suite
struct IterableFilterFindBindingTests {
    @Test(arguments: [
        ("Set<Int>", "setOf(1, 2, 3)", "kotlin.collections.Iterable"),
        ("MutableSet<Int>", "mutableSetOf(1, 2, 3)", "kotlin.collections.Iterable"),
        ("Collection<Int>", "setOf(1, 2, 3)", "kotlin.collections.Iterable"),
        ("Iterable<Int>", "setOf(1, 2, 3).asIterable()", "kotlin.collections.Iterable"),
        ("Set<Int>", "mapOf(1 to 1, 2 to 2, 3 to 3).keys", "kotlin.collections.Iterable"),
        ("List<Int>", "listOf(1, 2, 3)", "kotlin.collections.List"),
    ])
    func receiversBindThroughKIR(receiverType: String, factory: String, owner: String) throws {
        let source = """
        fun probe(values: \(receiverType)) {
            val filtered: List<Int> = values.filterIndexed { i, v -> v > i }
            val found: Int? = values.find { it > 1 }
        }
        fun main() {
            \(factory).filterIndexed { i, v -> v > i }
            \(factory).find { it > 1 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            var callCount = 0
            for index in ast.arena.exprs.indices {
                let id = ExprID(rawValue: Int32(index))
                guard let range = ast.arena.exprRange(id),
                      ctx.sourceManager.path(of: range.start.file) == path,
                      case let .memberCall(_, name, _, args, _) = ast.arena.expr(id),
                      ["filterIndexed", "find"].contains(ctx.interner.resolve(name)) else { continue }
                callCount += 1
                let callee = try #require(sema.bindings.callBinding(for: id)?.chosenCallee)
                #expect(sema.symbols.isSourceBackedSymbol(callee))
                #expect(sema.symbols.externalLinkName(for: callee) == nil)
                #expect(!sema.bindings.isCollectionHOFLambdaExpr(args[0].expr))
                let signature = try #require(sema.symbols.functionSignature(for: callee))
                let receiver = try #require(signature.receiverType)
                guard case let .classType(receiverClass) = sema.types.kind(of: sema.types.makeNonNullable(receiver)),
                      let symbol = sema.symbols.symbol(receiverClass.classSymbol) else {
                    Issue.record("Expected a nominal source extension receiver")
                    continue
                }
                #expect(symbol.fqName.map(ctx.interner.resolve).joined(separator: ".") == owner)
            }
            #expect(callCount == 4)
        }
    }
}
