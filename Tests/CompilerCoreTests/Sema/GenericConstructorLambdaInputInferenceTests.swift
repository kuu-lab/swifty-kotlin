#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericConstructorLambdaInputInferenceTests {
    // Keep the Sema gate focused; source/artifact compilation is covered by the CLI case.
    private func checkSources(_ sources: [String]) throws -> CompilationContext {
        var result: CompilationContext?
        try withTemporaryFiles(contents: sources + ["package kotlin\nobject Unit\nabstract class Number\ninterface CharSequence"]) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            result = ctx
        }
        return try #require(result)
    }

    private static let acceptedBodies: [String] = [
        "Host().accept(\"\", Holder { value: String -> Unit })",
        "val holder = Holder { value: String -> Unit }; Host().accept(\"\", holder)",
        "val holder = Holder { value: String -> Unit }; requiresString(holder)",
        "Host().accept<String>(\"\", Holder { value: String -> Unit })",
        "val holder: Holder<String> = Holder { value: String -> Unit }; Host().accept(\"\", holder)",
        "val holder = Holder<String> { value: String -> Unit }; requiresString(holder)",
        "val holder = Holder { value: String -> value.length }; requiresString(holder)",
    ]

    @Test
    func infersConstructorFromExplicitLambdaInput() throws {
        let sources = Self.acceptedBodies.enumerated().map { index, body in
            """
            package accepted\(index)
            class Holder<T>(val action: (T) -> Unit)
            class Host {
                fun <T> accept(value: T, holder: Holder<T>) {}
            }
            fun requiresString(holder: Holder<String>) {}
            fun sample() { \(body) }
            """
        }
        let ctx = try checkSources(sources)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let inputPaths = Set(ctx.options.inputs)
        var constructorCount = 0
        var lambdaCount = 0
        for index in ast.arena.exprs.indices {
            let id = ExprID(rawValue: Int32(index))
            guard let expression = ast.arena.expr(id),
                  let range = ast.arena.exprRange(id),
                  inputPaths.contains(ctx.sourceManager.path(of: range.start.file))
            else { continue }
            switch expression {
            case let .call(callee, _, _, _):
                guard case let .nameRef(name, _) = ast.arena.expr(callee),
                      name == ctx.interner.intern("Holder")
                else { continue }
                let type = try #require(sema.bindings.exprType(for: id))
                guard case let .classType(holder) = sema.types.kind(of: type) else {
                    Issue.record("Expected a Holder class type")
                    continue
                }
                #expect(holder.args == [.invariant(sema.types.stringType)])
                constructorCount += 1
            case .lambdaLiteral:
                let type = try #require(sema.bindings.exprType(for: id))
                guard case let .functionType(callback) = sema.types.kind(of: type) else {
                    Issue.record("Expected a callback function type")
                    continue
                }
                #expect(callback.params == [sema.types.stringType])
                #expect(callback.returnType == sema.types.unitType)
                lambdaCount += 1
            default:
                break
            }
        }
        #expect(constructorCount == Self.acceptedBodies.count)
        #expect(lambdaCount == Self.acceptedBodies.count)
    }

    private static let rejectedDeclarations: [String] = [
        "fun sample() { val holder = Holder<Int> { value: String -> Unit } }",
        "fun sample() { Host().accept<String>(7, Holder { value: String -> Unit }) }",
        "fun sample() { val holder = Holder { value: String -> Unit }; val typed: Holder<Any> = holder }",
        "fun <T> sample(): Holder<T> = Holder<T> { value: String -> Unit }",
        "fun <T> sample() { val action: (T) -> Unit = { value: String -> Unit } }",
        "class Bounded<T : Number>(val value: T, val action: (T) -> Unit); fun sample() { val holder = Bounded(\"wrong\") { value: String -> Unit } }",
        "class Bounded<T : Number>(val value: T, val action: (T) -> Unit); fun sample() { val holder = Bounded(7) { value: String -> Unit } }",
        "fun sample() { val holder = Holder<String?> { value: String -> Unit } }",
        "fun sample() { val holder = Holder { value -> Unit } }",
        "class Owner<T>(val action: (T) -> Unit) { fun sample() { val holder = Owner { value -> Unit } } }",
        "class Token<A>(val value: A); class Owner<T, U>(val action: (T) -> Unit, val data: U) { fun sample(data: Token<T>) { val holder = Owner({ value -> Unit }, data) } }",
        "class Token<A>(val value: A); class Owner<T, U>(val action: (T) -> Unit, val data: U) { fun sample(data: Token<T>) { val holder: Owner<*, Token<T>> = Owner({ value -> Unit }, data) } }",
    ]

    @Test
    func rejectsIncompatibleOrUninferredInputs() throws {
        let sources = Self.rejectedDeclarations.enumerated().map { index, declaration in
            """
            package rejected\(index)
            class Holder<T>(val action: (T) -> Unit)
            class Host {
                fun <T> accept(value: T, holder: Holder<T>) {}
            }
            \(declaration)
            """
        }
        let ctx = try checkSources(sources)
        for (index, path) in ctx.options.inputs.dropLast().enumerated() {
            let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
            #expect(!errors.isEmpty, "Invalid callback input must be rejected: \(Self.rejectedDeclarations[index])")
        }
    }

    private static let validControls: [String] = [
        """
        class Holder<T>(val action: (T) -> Unit)
        fun <T> sample(value: T) {
            val holder = Holder { input: T -> Unit }
            val typed: Holder<T> = holder
        }
        """,
        """
        class Holder<T : CharSequence>(val action: (T) -> Unit)
        fun sample() {
            val holder = Holder { input: String -> Unit }
            val typed: Holder<String> = holder
        }
        """,
        """
        class Holder<T>(val action: (T) -> Unit) {
            fun again() {
                val holder = Holder { input: T -> Unit }
                val typed: Holder<T> = holder
            }
            fun withExpectedType(): Holder<T> = Holder { input: T -> Unit }
            fun unannotatedExpected(): Holder<T> = Holder { input -> Unit }
            fun explicit() { val holder = Holder<T> { input -> Unit } }
            fun stored() { val holder = Holder(action) }
        }
        """,
        """
        class Holder<T : Number>(val action: (T) -> Unit)
        fun sample() { val holder = Holder { input: Int -> Unit } }
        """,
        """
        class Holder<T>(val action: (T) -> Unit)
        fun <T : Number> factory(action: (T) -> Unit): Holder<T> = Holder(action)
        fun sample() { val holder = factory { input: Int -> Unit } }
        """,
        """
        class Factory<R> { fun <T : Number> make(action: (T) -> R) {} }
        fun sample() { Factory<Unit>().make { input: Int -> Unit } }
        """,
        """
        class Holder<T>(val first: (T) -> Unit, val second: (T) -> Unit)
        fun sample() {
            val holder = Holder({ input -> Unit }, { input: String -> Unit })
            val typed: Holder<String> = holder
            val reversed = Holder({ input: String -> Unit }, { input -> Unit })
            val reversedTyped: Holder<String> = reversed
        }
        """,
        """
        class Holder<T>(val value: T)
        class Host { fun <T> accept(value: T, holder: Holder<T>) {} }
        fun sample() { Host().accept("", Holder("")) }
        """,
    ]

    @Test
    func preservesValidBoundsAndOrdinaryConstructors() throws {
        let sources = Self.validControls.enumerated().map { index, source in
            "package control\(index)\n" + source
        }
        let ctx = try checkSources(sources)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }
}
#endif
