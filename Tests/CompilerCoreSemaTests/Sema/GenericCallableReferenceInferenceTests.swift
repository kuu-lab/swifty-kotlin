#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct GenericCallableReferenceInferenceTests {
    private func makeStarProjectionContext(_ source: String) -> CompilationContext {
        let path = "/virtual/star-projection-callable-reference-\(UUID().uuidString).kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [
        "val ref: (Int) -> Int = ::identity; ref(42)",
        "val ref: (String) -> String = ::identity; ref(\"hello\")",
        "val ref: (Int?) -> Int? = ::identity; ref(null)",
        "val ref: (Int) -> Any = ::identity; ref(42)",
        "val ref: (List<Int>) -> List<Int> = ::identity; ref(listOf(42))",
        "use(::identity)",
        "useGeneric<Int>(::identity)",
    ])
    func infersFromContext(body: String) throws {
        let ctx = makeContextFromSource("""
        fun <T> identity(value: T): T = value
        fun use(ref: (Int) -> Int): Int = ref(42)
        fun <T> useGeneric(ref: (T) -> T) {}
        fun main() { \(body) }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let type = try #require(sema.bindings.exprType(for: ref))
        #expect(!sema.types.typeContainsAnyTypeParam(type))
        #expect(sema.bindings.callableRefKind(for: ref) == .functionRef)
    }

    @Test(arguments: [
        "fun ref(): (Int) -> Int = ::identity",
        "val ref: (Int) -> Int = ::identity",
        "fun <T> first(a: T, b: T): T = a; val ref: (Int, Int) -> Int = ::first",
        "fun <A, B> second(a: A, b: B): B = b; val ref: (Int, String) -> String = ::second",
        "fun <T : String> make(): T = TODO(); val ref: () -> Any = ::make",
        "fun <T, C : List<T>> firstIn(values: C): T = values[0]; val ref: (List<Int>) -> Int = ::firstIn",
        "class Box<T> { fun <R> transform(value: R): R = value }; fun ref(box: Box<String>) { val f: (Int) -> Int = box::transform }",
        "class Box { fun <T> identity(value: T): T = value }; val ref: (Box, Int) -> Int = Box::identity",
        "fun <T> T.copy(): T = this; val ref: (String) -> String = String::copy",
        "fun <T> T.copy(): T = this; fun ref(value: String) { val f: () -> String = value::copy }",
        """
        fun interface IntOp { fun apply(value: Int): Int }
        fun useOp(op: IntOp): Int = op.apply(42)
        fun main() { useOp(::identity) }
        """,
    ])
    func supportsOtherCallableContexts(declaration: String) throws {
        let ctx = makeContextFromSource("""
        fun <T> identity(value: T): T = value
        \(declaration)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
    }

    @Test
    func infersGenericArgumentsFromReflectiveCallableReturnType() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KFunction
        fun <T> collect(vararg values: T): Array<out T> = values
        fun <T : CharSequence> collectBounded(vararg values: T): Array<out T> = values
        fun main() {
            val generic: KFunction<Array<out String>> = ::collect
            val bounded: KFunction<Array<out String>> = ::collectBounded
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Unexpected errors: \(errors)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        // The bundled stdlib is compiled alongside the input, so its own
        // callable references also populate the binding table. Scope the
        // assertions to this file's two references.
        let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .callableRef(_, member, _) = ast.arena.expr(exprID),
                  ["collect", "collectBounded"].contains(ctx.interner.resolve(member))
            else {
                return nil
            }
            return exprID
        }
        try #require(references.count == 2)
        for reference in references {
            let binding = try #require(sema.bindings.callableReferenceBindings[reference])
            let type = try #require(sema.bindings.exprType(for: reference))
            #expect(!sema.types.typeContainsAnyTypeParam(type))
            let argument = try #require(binding.substitutedTypeArguments.first)
            #expect(
                sema.types.isSubtype(argument, sema.types.stringType),
                "Expected String-compatible inference, got \(sema.types.displayName(of: argument, symbols: sema.symbols, interner: ctx.interner))"
            )
            if ctx.interner.resolve(sema.symbols.symbol(binding.chosenCallee)?.name ?? .invalid) == "collectBounded",
               let charSequence = sema.types.charSequenceInterfaceSymbol
            {
                let bound = sema.types.make(.classType(ClassType(classSymbol: charSequence)))
                #expect(
                    sema.types.isSubtype(argument, bound),
                    "Bounded inference must retain CharSequence, got \(sema.types.displayName(of: argument, symbols: sema.symbols, interner: ctx.interner))"
                )
            }
        }
    }

    @Test func adaptsVarargAndTrailingDefaultArguments() throws {
        let ctx = makeContextFromSource("""
        fun useArray(factory: (Int, Int) -> Array<Int>): Array<Int> = factory(11, 22)
        fun combine(first: Int = 3, second: Int = 4): Int = first * 10 + second
        fun collect(vararg values: Int) {}
        fun main() {
            val values: Array<Int> = useArray(::arrayOf)
            val noArguments: () -> Int = ::combine
            val oneArgument: (Int) -> Int = ::combine
            val packed: (IntArray) -> Unit = ::collect
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected vararg/default adaptations to type-check, got: \(errors)")
        let sema = try #require(ctx.sema)
        let bindings = sema.bindings.callableReferenceBindings.values
        #expect(bindings.filter(\.isCallableReferenceAdapter).count == 3)
    }

    @Test
    func infersGenericCallableReferenceFromStarProjectedHigherOrderArgument() throws {
        let ctx = makeStarProjectionContext("""
        class MutableList<T>
        fun <T> T.also(block: (T) -> Unit): T = this
        fun <T> mutate(value: MutableList<T>): MutableList<T> = value
        fun use(value: MutableList<*>): MutableList<*> = value.also(::mutate)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected star-projected callable reference to infer its captured type, got: \(errors)")
    }

    @Test
    func rejectsStarProjectedCallableReferenceWhenTypeParameterBoundIsNarrower() throws {
        let ctx = makeStarProjectionContext("""
        class MutableList<T>
        fun <T> T.also(block: (T) -> Unit): T = this
        fun <T : Any> mutate(value: MutableList<T>): MutableList<T> = value
        fun use(value: MutableList<*>): MutableList<*> = value.also(::mutate)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0001" })
    }

    @Test(arguments: [
        "fun <T> identity(value: T): T = value; val ref: (Int) -> String = ::identity",
        "fun <T : String> identity(value: T): T = value; val ref: (Int) -> Int = ::identity",
        "fun <T : Any> identity(value: T): T = value; val ref: (Int?) -> Int? = ::identity",
        "fun <T> identity(value: T): T = value; val ref: (Int, Int) -> Int = ::identity",
        "fun combine(first: Int = 0, second: String = \"x\"): String = second; val ref: (String) -> String = ::combine",
        "suspend fun <T> identity(value: T): T = value; val ref: (Int) -> Int = ::identity",
        "fun <T> unused(value: Int): Int = value; val ref: (Int) -> Int = ::unused",
        "fun <T> T.echo(value: T): T = value; fun ref(value: String) { val f: (Int) -> Int = value::echo }",
    ])
    func rejectsInvalidReference(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        // Callable-reference specialization reports its own constraint
        // failure rather than the initializer path's dedicated code.
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001"
        })
    }

    @Test(arguments: [false, true])
    func choosesApplicableOverload(preferConcrete: Bool) throws {
        let other = preferConcrete
            ? "fun choose(value: Int): Int = value + 1"
            : "fun choose(value: String): String = value"
        let ctx = makeContextFromSource("""
        fun <T> choose(value: T): T = value
        \(other)
        fun main() { val ref: (Int) -> Int = ::choose }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let ref = try #require(firstExprID(in: ast) { _, expr in
            if case .callableRef = expr { return true }
            return false
        })
        let chosen = try #require(sema.bindings.identifierSymbol(for: ref))
        let signature = try #require(sema.symbols.functionSignature(for: chosen))
        #expect(signature.typeParameterSymbols.isEmpty == preferConcrete)
    }

    @Test(arguments: [
        // MVIKotlin shape: class type parameters map onto the call's
        // inference variables; `S` is pinned by the sibling argument.
        """
        interface Executor<I, S>
        class Bypass<I : Any, S : Any> : Executor<I, S>
        fun <I : Any, S : Any> create(executorFactory: () -> Executor<I, S>, s: S): () -> Executor<I, S> = executorFactory
        val f = create(::Bypass, 0)
        """,
        // Both call type parameters are pinned by sibling arguments.
        """
        interface Executor<I, S>
        class Bypass<I : Any, S : Any> : Executor<I, S>
        fun <I : Any, S : Any> create(executorFactory: () -> Executor<I, S>, s: S, i: I) = executorFactory
        val f = create(::Bypass, 0, "x")
        """,
        // Overloaded constructors: the expected `() -> Executor<I>` signature
        // selects the zero-argument constructor while `I` is inferred.
        """
        interface Executor<I>
        class Bypass<I : Any>(val x: Int) : Executor<I> {
            constructor() : this(0)
            constructor(s: String) : this(s.length)
        }
        fun <I : Any> create(executorFactory: () -> Executor<I>) = executorFactory
        val f = create<Int>(::Bypass)
        """,
    ])
    func infersGenericConstructorReferenceInsideGenericCall(source: String) throws {
        // KUU-3974: `::Bypass`-style constructor references must specialize
        // against the surrounding generic call instead of leaking the
        // constructor's lexical type parameters into the outer solver.
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected generic constructor reference to infer from the call, got: \(errors)")
    }

    @Test
    func stillRejectsAmbiguousConstructorReferenceWithoutExpectedType() throws {
        // `::C` with multiple constructors and no expected function type must
        // stay ambiguous, matching kotlinc.
        let ctx = makeContextFromSource("""
        class C(val a: Int) {
            constructor(a: Int, b: Int) : this(a)
        }
        val ref = ::C
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.severity == .error && $0.code == "KSWIFTK-TYPE-0001"
        })
    }

    @Test
    func specializesGenericReferenceAgainstLexicalExpectedTypeParameters() throws {
        // KUU-4204: an expected type that only mentions the enclosing
        // declaration's own (rigid) type parameters still specializes the
        // reference, matching `createSegmentFunction` in kotlinx-coroutines.
        let ctx = makeContextFromSource("""
        class Box<T>(val value: T)
        fun <E> mk(value: E): Box<E> = Box(value)
        fun <T> make(): (T) -> Box<T> = ::mk
        fun <T> makeLocal(): (T) -> Box<T> {
            val ref: (T) -> Box<T> = ::mk
            return ref
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected generic reference to specialize against rigid type parameters, got: \(errors)")
    }

    @Test
    func resolvesOverloadedReferencesFromGenericCallResultType() throws {
        let ctx = makeContextFromSource("""
        fun foo(x: Int?) {}
        fun foo(y: String?) {}
        fun foo(z: Boolean) {}
        fun <T> bar(f: (T) -> Unit, name: String): T? = null
        fun main() {
            val intResult: Int? = bar(::foo, "Int")
            val stringResult: String? = bar(::foo, "String")
            val booleanResult: Boolean? = bar<Boolean>(::foo, "Boolean")
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Expected result context to resolve overloaded references, got: \(errors)")

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let inputPath = try #require(ctx.options.inputs.first)
        let userFileID = try #require(ctx.sourceManager.fileID(forPath: inputPath))
        let inputTypeNames = ast.arena.exprs.indices.compactMap { index -> TypeID? in
            let reference = ExprID(rawValue: Int32(index))
            guard ast.arena.exprRange(reference)?.start.file == userFileID,
                  case .callableRef = ast.arena.expr(reference),
                  let target = sema.bindings.identifierSymbol(for: reference),
                  let signature = sema.symbols.functionSignature(for: target)
            else { return nil }
            return signature.parameterTypes.first
        }.map {
            sema.types.displayName(of: $0, symbols: sema.symbols, interner: ctx.interner)
        }
        #expect(inputTypeNames == ["Int?", "String?", "Boolean"])
    }
}
#endif
