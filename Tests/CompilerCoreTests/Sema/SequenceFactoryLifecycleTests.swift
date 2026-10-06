@testable import CompilerCore
import Testing

@Suite
struct SequenceFactoryLifecycleTests {
    // KUU-1073: a nullable callback result must infer T = Int, not Int?.
    @Test(arguments: [
        "generateSequence { if (true) 1 else null }",
        "generateSequence { 1 as Int? }",
        "generateSequence { i = i + 1; if (i <= 3) i else null }",
        "generateSequence { 1 }",
    ])
    func nullableGeneratorLambdaInfersNonNullableElement(expression: String) throws {
        let source = """
        fun probe() {
            var i = 0
            val values = \(expression)
        }
        """
        try withTemporaryFile(contents: source) { path in
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
            #expect(binding.substitutedTypeArguments == [sema.types.intType])
            let resultType = try #require(sema.bindings.exprType(for: call))
            guard case let .classType(sequence) = sema.types.kind(of: resultType) else {
                Issue.record("Expected Sequence<Int>, got \(sema.types.renderType(resultType))")
                return
            }
            #expect(sequence.args == [.invariant(sema.types.intType)])
        }
    }

    @Test(arguments: [
        "val values: Sequence<String> = generateSequence { if (true) 1 else null }",
        "val values = generateSequence<Int?> { 1 as Int? }",
    ])
    func nullableGeneratorStillRejectsIncompatibleTypes(statement: String) throws {
        try withTemporaryFile(contents: "fun probe() { \(statement) }") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected rejection of \(statement)")
        }
    }

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
        ("generateSequence<Int>(seedFunction = { throw IllegalStateException(\"retry\") }, nextFunction = { null })", ["seedFunction", "nextFunction"]),
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

    @Test
    func genericGeneratorUsesCanonicalSource() throws {
        let source = """
        fun <T : Any> probe(seed: () -> T?, next: (T) -> T?): Sequence<T> =
            generateSequence(seedFunction = seed, nextFunction = next)
        """
        try withTemporaryFile(contents: source) { path in
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
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let file = try #require(sema.symbols.sourceFileID(for: chosen))
            #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/sequences/SequenceFactories.kt")
            #expect(sema.symbols.externalLinkName(for: chosen) == nil)
            #expect(sema.symbols.symbol(chosen)?.flags.contains(.synthetic) == false)
        }
    }

    @Test(arguments: [
        ("Iterator<String?>", "iterator"),
        ("Iterable<String?>", "elements"),
        ("Sequence<String?>", "sequence"),
    ])
    func nullableYieldAllUsesCanonicalScopeAndParameterNames(argument: String, parameter: String) throws {
        let source = "suspend fun SequenceScope<String?>.probe(values: \(argument)) { this.yieldAll(\(parameter) = values) }"
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let call = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .memberCall(_, name, _, _, _) = expr else { return false }
                return ctx.interner.resolve(name) == "yieldAll"
            })
            let chosen = try #require(sema.bindings.callBinding(for: call)?.chosenCallee)
            let info = try #require(sema.symbols.symbol(chosen))
            #expect(info.fqName.map(ctx.interner.resolve) == ["kotlin", "sequences", "SequenceScope", "yieldAll"])
            #expect(!info.flags.contains(.synthetic))
            let file = try #require(sema.symbols.sourceFileID(for: chosen))
            #expect(ctx.sourceManager.path(of: file) == "__bundled_kotlin/sequences/SequenceScope/SequenceScope.kt")
            let signature = try #require(sema.symbols.functionSignature(for: chosen))
            #expect(signature.valueParameterSymbols.compactMap { sema.symbols.symbol($0).map { ctx.interner.resolve($0.name) } } == [parameter])
        }
    }
}
