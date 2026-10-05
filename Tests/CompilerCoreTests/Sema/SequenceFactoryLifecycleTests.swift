@testable import CompilerCore
import Testing

@Suite
struct SequenceFactoryLifecycleTests {
    @Test(arguments: [
        "Sequence(iterator = { listOf(1).iterator() })",
        "Sequence({ listOf(1).iterator() })",
        "Sequence { listOf(1).iterator() }",
    ])
    func factoryUsesCanonicalSourceAndIteratorParameter(expression: String) throws {
        try withTemporaryFile(contents: "fun probe(): Sequence<Int> = \(expression)") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "Sequence"
            })
            let binding = try #require(sema.bindings.callBinding(for: call))
            let chosen = try #require(binding.chosenCallee)
            let symbol = try #require(sema.symbols.symbol(chosen))
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            let file = try #require(sema.symbols.sourceFileID(for: chosen))
            #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/sequences/SequenceFactories.kt")
            #expect(symbol.visibility == .public)
            #expect(!symbol.flags.contains(.synthetic))
            #expect(symbol.flags.contains(.inlineFunction))
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            #expect(signature.valueParameterAllowsNonLocalReturn == [false])
            #expect(signature.valueParameterSymbols.compactMap {
                sema.symbols.symbol($0).map { ctx.interner.resolve($0.name) }
            } == ["iterator"])
            let declarations = sema.symbols.lookupAll(fqName: [
                "kotlin", "sequences", "Sequence",
            ].map(ctx.interner.intern))
            #expect(declarations.filter { sema.symbols.symbol($0)?.kind == .function } == [chosen])
        }
    }

    @Test(arguments: [
        ("generateSequence<Int>(nextFunction = { null })", ["nextFunction"]),
        ("generateSequence(seed = 1, nextFunction = { null })", ["seed", "nextFunction"]),
        ("generateSequence<Int>(seedFunction = { 1 }, nextFunction = { null })", ["seedFunction", "nextFunction"]),
    ])
    func generatorOverloadsKeepCanonicalSourceAndParameterNames(expression: String, parameters: [String]) throws {
        try withTemporaryFile(contents: "fun probe(): Sequence<Int> = \(expression)") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(name, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(name) == "generateSequence"
            })
            let binding = try #require(sema.bindings.callBinding(for: call))
            let chosen = try #require(binding.chosenCallee)
            let file = try #require(sema.symbols.sourceFileID(for: chosen))
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/sequences/SequenceFactories.kt")
            #expect(signature.valueParameterSymbols.compactMap {
                sema.symbols.symbol($0).map { ctx.interner.resolve($0.name) }
            } == parameters)
        }
    }
}
