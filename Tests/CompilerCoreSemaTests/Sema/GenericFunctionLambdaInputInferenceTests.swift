#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericFunctionLambdaInputInferenceTests {
    private func checkSources(_ sources: [String]) throws -> (context: CompilationContext, paths: [String]) {
        var result: CompilationContext?
        var inputPaths: [String] = []
        try withTemporaryFiles(contents: sources + ["package kotlin\nobject Unit"]) { paths in
            inputPaths = Array(paths.dropLast())
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            result = ctx
        }
        return (try #require(result), inputPaths)
    }

    @Test
    func infersGenericFunctionTypesFromExplicitLambdaInputs() throws {
        let fixture = try checkSources([
            """
            package accepted
            fun <A> fold(seed: A, step: (Int, A) -> A): A = step(1, seed)
            fun <T> choose(seed: T?, step: (T) -> T?): T? = seed

            fun <A> overloaded(seed: A, step: (Int, A) -> A): A = step(1, seed)
            fun overloaded(seed: Int, step: (Int, String) -> String): String = step(1, "")

            fun sample(): Long? {
                val inferred = fold(0) { element: Int, accumulator: Long -> accumulator + element }
                val explicit = fold<Long>(0) { element: Int, accumulator: Long -> accumulator + element }
                val longSeed = fold(0L) { element: Int, accumulator: Long -> accumulator + element }
                val intSeed = fold(0) { element: Int, accumulator: Int -> accumulator + element }
                val selected = overloaded(0) { element: Int, accumulator: Long -> accumulator + element }
                val nullable: Long? = choose(null) { value: Long -> value }
                return nullable
            }
            """,
            """
            package rejected
            fun <A> fold(seed: A, step: (Int, A) -> A): A = step(1, seed)
            fun sample() {
                val seed: Int = 0
                fold(seed) { element: Int, accumulator: Long -> accumulator + element }
            }
            """,
            """
            package ambiguous
            fun <T> select(marker: Int = 0, step: (T) -> Unit) {}
            fun <T> select(marker: String = "", step: (T) -> Unit) {}
            fun sample() { select { value: String -> Unit } }
            """,
        ])

        let ctx = fixture.context
        let acceptedPath = fixture.paths[0]
        let acceptedErrors = diagnosticsForPath(acceptedPath, in: ctx).filter { $0.severity == .error }
        #expect(acceptedErrors.isEmpty, "Expected typed lambda inputs to infer the generic call arguments, got: \(acceptedErrors)")

        let rejectedErrors = diagnosticsForPath(fixture.paths[1], in: ctx).filter { $0.severity == .error }
        #expect(!rejectedErrors.isEmpty, "A typed nonconstant Int seed must not widen to Long")

        let ambiguousErrors = diagnosticsForPath(fixture.paths[2], in: ctx).filter { $0.severity == .error }
        #expect(
            ambiguousErrors.contains { $0.code == "KSWIFTK-SEMA-0003" },
            "An explicitly typed generic call with equally applicable candidates must remain ambiguous: \(ambiguousErrors)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var foldTypeArguments: [TypeID] = []
        var selectedOverload: SymbolID?
        var nullableTypeArgument: TypeID?
        for index in ast.arena.exprs.indices {
            let expressionID = ExprID(rawValue: Int32(index))
            guard let range = ast.arena.exprRange(expressionID),
                  ctx.sourceManager.path(of: range.start.file) == acceptedPath,
                  case let .call(callee, _, _, _) = ast.arena.expr(expressionID),
                  case let .nameRef(name, _) = ast.arena.expr(callee),
                  let binding = sema.bindings.callBinding(for: expressionID),
                  let symbol = sema.symbols.symbol(binding.chosenCallee)
            else { continue }
            switch ctx.interner.resolve(name) {
            case "fold":
                foldTypeArguments.append(contentsOf: binding.substitutedTypeArguments)
            case "overloaded":
                selectedOverload = binding.chosenCallee
                #expect(binding.substitutedTypeArguments == [sema.types.longType])
            case "choose":
                nullableTypeArgument = binding.substitutedTypeArguments.first
            default:
                break
            }
            _ = symbol
        }
        #expect(foldTypeArguments.count == 4)
        #expect(Array(foldTypeArguments.prefix(3)) == Array(repeating: sema.types.longType, count: 3))
        #expect(foldTypeArguments.last == sema.types.intType)
        #expect(selectedOverload != nil)
        #expect(nullableTypeArgument == sema.types.longType)
    }
}
#endif
