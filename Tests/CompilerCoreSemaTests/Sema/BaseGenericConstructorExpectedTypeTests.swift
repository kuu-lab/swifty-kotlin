#if canImport(Testing)
@testable import CompilerCore
import Testing
import Foundation
import TestStdlibCache
@testable import CompilerTestSupport

@Suite
struct BaseGenericConstructorExpectedTypeTests {
    @Test(arguments: [
        "ParsedValue(Separated(emptyList(), emptyList()))",
        "ParsedValue(Separated<T, S>(emptyList(), emptyList()))",
        "ParsedValue<Separated<T, S>>(Separated(emptyList(), emptyList()))",
    ], [false, true])
    func baseExpectedTypeContextualizesNestedConstructor(expression: String, fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        open class ParseResult<out T>
        class ParsedValue<out T>(val value: T) : ParseResult<T>()
        class Separated<T, S>(val terms: List<T>, val separators: List<S>)
        fun <T, S> emptyResult(): ParseResult<Separated<T, S>> = \(expression)
        """, fromSource: fromSource)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func sameClassExpectedTypeStillContextualizesNestedConstructor() throws {
        let ctx = try makeTestContext("""
        class ParsedValue<out T>(val value: T)
        class Separated<T, S>(val terms: List<T>, val separators: List<S>)
        fun <T, S> emptyResult(): ParsedValue<Separated<T, S>> =
            ParsedValue(Separated(emptyList(), emptyList()))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func multilevelBaseWithReorderedParametersContextualizesNestedConstructor() throws {
        let ctx = try makeTestContext("""
        open class Base<A, B>
        open class Middle<X, Y> : Base<Y, X>()
        class PairBox<T, S>(val terms: List<T>, val separators: List<S>)
        class Child<X, Y>(val value: PairBox<X, Y>) : Middle<X, Y>()
        fun <T, S> result(): Base<S, T> = Child(PairBox(emptyList(), emptyList()))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func genericFactoryWithBaseExpectedTypeContextualizesNestedConstructor() throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Child<out T>(val value: T) : Base<T>()
        class Box<T>(val items: List<T>)
        fun <T> wrap(value: T): Child<T> = Child(value)
        fun <T> result(): Base<Box<T>> = wrap(Box(emptyList()))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func baseExpectedTypeContextualizesConstructorLambda() throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Child<T>(val transform: (T) -> T) : Base<T>()
        fun result(): Base<Int> = Child { it + 1 }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func explicitConstructorTypeArgumentKeepsItsNarrowerType() throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Child<out T>(val value: T) : Base<T>()
        fun result(): Base<Any> = Child<String>("value")
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "Child", in: ast, interner: ctx.interner))
        let type = try #require(sema.bindings.exprType(for: call))
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            Issue.record("Expected a Child class type")
            return
        }
        #expect(classType.args == [.invariant(sema.types.stringType)])
    }

    @Test(arguments: [
        "Child(Box(listOf(1)))",
        "Child<Box<Int>>(Box(emptyList()))",
        "Unrelated(Box(emptyList()))",
    ])
    func incompatibleInvariantOrUnrelatedBaseStillFails(expression: String) throws {
        let ctx = try makeTestContext("""
        open class Base<T>
        class Child<T>(val value: T) : Base<T>()
        class Unrelated<T>(val value: T)
        class Box<T>(val items: List<T>)
        fun result(): Base<Box<String>> = \(expression)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "Expected incompatible base type to fail")
    }

    @Test func repeatedCovariantBaseParameterDoesNotOverwriteNarrowerArgument() throws {
        let ctx = try makeTestContext("""
        open class Base<out A, out B>
        class Box<T>(val value: T)
        class Derived<T>(val value: Box<T>) : Base<T, T>()
        fun result(): Base<Int, Number> = Derived(Box(1))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func repeatedInvariantBaseParameterStillRejectsIncompatibleArguments() throws {
        let ctx = try makeTestContext("""
        open class Base<A, B>
        class Box<T>(val value: T)
        class Derived<T>(val value: Box<T>) : Base<T, T>()
        fun result(): Base<Int, Number> = Derived(Box(1))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty)
    }

    @Test(arguments: [true, false])
    func covariantBaseExpectationRespectsConstructorUpperBound(valid: Bool) throws {
        let value = valid ? "1" : "\"value\""
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Box<T>(val value: T)
        class Child<T : Number>(val value: Box<T>) : Base<T>()
        fun result(): Base<Any> = Child(Box(\(value)))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty == valid, "\(errors)")
    }

    @Test(arguments: ["Base<in T>", "Base<T>"])
    func contravariantBaseExpectationPreservesWiderNestedArgument(baseType: String) throws {
        let declaration = baseType == "Base<in T>" ? "in T" : "T"
        let expectedArgument = baseType == "Base<in T>" ? "String" : "in String"
        let ctx = try makeTestContext("""
        open class Base<\(declaration)>
        class Box<T>(val value: T)
        class Child<T>(val value: Box<T>) : Base<T>()
        fun anyValue(): Any = 1
        fun result(): Base<\(expectedArgument)> = Child(Box(anyValue()))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [false, true], [false, true])
    func overloadContextsRequireAgreement(reverseCandidates: Bool, agree: Bool) throws {
        let secondType = agree ? "T" : "List<T>"
        let compilation = try makeTestContext("""
        open class Base<T>
        class Box<T>(val items: List<T>)
        class Child<T> : Base<T> {
            constructor(value: Box<T>)
            constructor(value: Box<\(secondType)>, marker: Int = 0)
        }
        fun seed(): Box<String> = Box(emptyList())
        """)
        try runSema(compilation)
        #expect(!compilation.diagnostics.hasError)
        let sema = try #require(compilation.sema)
        let ast = try #require(compilation.ast)
        let base = try #require(sema.symbols.lookup(fqName: [compilation.interner.intern("Base")]))
        let child = try #require(sema.symbols.lookup(fqName: [compilation.interner.intern("Child")]))
        var candidates = sema.symbols.allSymbols().filter {
            $0.kind == .constructor && sema.symbols.parentSymbol(for: $0.id) == child
        }.map(\.id)
        #expect(candidates.count == 2)
        if reverseCandidates { candidates.reverse() }
        let nestedCall = try #require(nameRefCallExprID(named: "Box", in: ast, interner: compilation.interner))
        let resolver = OverloadResolver()
        let dataFlow = DataFlowAnalyzer()
        let driver = TypeCheckDriver(
            ast: ast, sema: sema, solver: ConstraintSolver(), resolver: resolver,
            dataFlow: dataFlow, interner: compilation.interner,
            diagnostics: compilation.diagnostics, semaCacheContext: nil
        )
        let ctx = TypeInferenceContext(
            ast: ast, sema: sema, resolver: resolver, dataFlow: dataFlow,
            interner: compilation.interner, scope: FileScope(parent: nil, symbols: sema.symbols),
            implicitReceiverType: nil, loopDepth: 0, loopLabelStack: [], lambdaLabelStack: [],
            exportBlockLocalsForExpr: nil, flowState: DataFlowState(), currentFileID: ast.files[0].fileID,
            enclosingClassSymbol: nil, visibilityChecker: VisibilityChecker(symbols: sema.symbols, interner: compilation.interner),
            outerReceiverTypes: [], semaCacheContext: nil, useNewInference: false,
            useUnrestrictedBuilderInference: false, useProperTypeInferenceConstraintsProcessing: false,
            globalOptInMarkerNames: []
        )
        let expected = sema.types.make(.classType(ClassType(
            classSymbol: base, args: [.invariant(sema.types.stringType)], nullability: .nonNull
        )))
        var overrides: [Int: TypeID] = [:]
        var lambdaContexts: [Int: TypeInferenceContext] = [:]
        let callRange = ast.arena.exprRange(nestedCall) ?? SourceRange(
            start: CompilerCore.SourceLocation(file: ast.files[0].fileID, offset: 0),
            end: CompilerCore.SourceLocation(file: ast.files[0].fileID, offset: 0)
        )
        driver.callChecker.prepareCallExprArgumentContexts(
            args: [CallArgument(expr: nestedCall)], callRange: callRange, ctx: ctx, expectedType: expected,
            explicitTypeArgs: [], calleeName: compilation.interner.intern("Child"),
            candidates: candidates, locals: [:], withContextExpectedLambdaType: nil,
            expectedTypeOverrides: &overrides, lambdaContextOverrides: &lambdaContexts
        )
        if agree {
            let box = try #require(sema.symbols.lookup(fqName: [compilation.interner.intern("Box")]))
            let expectedBox = sema.types.make(.classType(ClassType(
                classSymbol: box, args: [.invariant(sema.types.stringType)], nullability: .nonNull
            )))
            #expect(overrides[0] == expectedBox)
        } else {
            #expect(overrides.isEmpty, "Conflicting overload contexts must abstain in either order")
        }
    }

    @Test(arguments: [true, false])
    func dependentConstructorBoundsDiscardUnusableSeeds(valid: Bool) throws {
        let value = valid ? "1" : "\"value\""
        let ctx = try makeTestContext("""
        open class Base<out A, out B>
        class Box<T>(val value: T)
        class Child<A : Number, B : A>(val first: A, val second: Box<B>) : Base<A, B>()
        fun result(): Base<Any, Any> = Child(1, Box(\(value)))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty == valid, "\(errors)")
    }

    @Test(arguments: ["Any", "String"])
    func covariantBaseHintDoesNotRejectFixedNestedReturnType(expected: String) throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Box<T>(val value: T)
        class Child<T>(val value: Box<T>) : Base<T>()
        fun intBox(): Box<Int> = Box(1)
        fun result(): Base<\(expected)> = Child(intBox())
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty == (expected == "Any"), "\(errors)")
    }

    @Test func covariantBaseHintDoesNotRejectExplicitLambdaParameter() throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Child<T>(val transform: (T) -> T) : Base<T>()
        fun result(): Base<Any> = Child { value: String -> value }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: ["Int", "String"])
    func otherInvariantArgumentCanRefineCovariantBaseHint(element: String) throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Box<T>(val value: T)
        class Child<T>(val first: Box<T>, val second: Box<T>) : Base<T>()
        fun result(other: Box<\(element)>): Base<Any> = Child(Box(1), other)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty == (element == "Int"), "\(errors)")
    }

    @Test func qualifiedConstructorCanRetryCovariantBaseHint() throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Box<T>(val value: T)
        class Holder {
            class Child<T>(val first: Box<T>, val second: Box<T>) : Base<T>()
        }
        fun result(other: Box<Int>): Base<Any> = Holder.Child(Box(1), other)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func qualifiedConstructorRetryPreservesImplicitLambdaContext() throws {
        let ctx = try makeTestContext("""
        open class Base<out T>
        class Box<T>(val value: T)
        class Holder {
            class Child<T>(val transform: (T) -> T, val second: Box<T>) : Base<T>()
        }
        fun result(other: Box<String>): Base<Any> = Holder.Child({ it }, other)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    /// KUU-3937: inside a member function the expected type references the
    /// class's own type parameter, which is also the constructor's inference
    /// variable symbol. Decomposing `POS<E'> <: PS<E>` must still pin E' := E.
    @Test(arguments: [false, true])
    func memberFunctionExpectedSupertypePinsOwnClassTypeParameter(fromSource: Bool) throws {
        let ctx = try makeTestContext("""
        interface PS<E>
        class POS<E>(val a: Any?, val b: Any?) : PS<E> {
            fun add(element: E): PS<E> = POS(element, element)
        }
        """, fromSource: fromSource)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "POS", in: ast, interner: ctx.interner))
        let type = try #require(sema.bindings.exprType(for: call))
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            Issue.record("Expected a POS class type")
            return
        }
        let pos = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("POS")]))
        let parameter = try #require(sema.types.allTypeParameterSymbols(for: pos).first)
        let lexicalParameter = sema.types.make(.typeParam(TypeParamType(
            symbol: parameter, nullability: .nonNull
        )))
        #expect(classType.args == [.invariant(lexicalParameter)])
    }

    /// Same collision through a constructor parameter that itself mentions the
    /// class type parameter, matching kotlinx.collections.immutable
    /// `PersistentOrderedSet.add`.
    @Test func memberFunctionExpectedSupertypePinsParameterUsedInOtherParameter() throws {
        let ctx = try makeTestContext("""
        interface PMap<K, V>
        interface PS<E>
        class Links
        class POS<E>(val first: Any?, val second: Any?, val map: PMap<E, Links>) : PS<E> {
            fun add(element: E, map: PMap<E, Links>): PS<E> = POS(element, element, map)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    /// A lexical parameter nested inside the expected type argument is real
    /// evidence too, not a self-collision: `POS<E'> <: PS<Wrap<E>>` must bind
    /// `E' = Wrap<E>`, which the same-symbol pin must not override.
    @Test func memberFunctionExpectedSupertypeKeepsNestedParameterInference() throws {
        let ctx = try makeTestContext("""
        interface PS<E>
        class Wrap<T>(val v: T)
        class POS<E>(val a: Any?) : PS<E> {
            fun nested(element: E): PS<Wrap<E>> = POS(element)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(nameRefCallExprID(named: "POS", in: ast, interner: ctx.interner))
        let type = try #require(sema.bindings.exprType(for: call))
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            Issue.record("Expected a POS class type")
            return
        }
        let pos = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("POS")]))
        let wrap = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Wrap")]))
        let parameter = try #require(sema.types.allTypeParameterSymbols(for: pos).first)
        let lexicalParameter = sema.types.make(.typeParam(TypeParamType(
            symbol: parameter, nullability: .nonNull
        )))
        let wrappedParameter = sema.types.make(.classType(ClassType(
            classSymbol: wrap, args: [.invariant(lexicalParameter)], nullability: .nonNull
        )))
        #expect(classType.args == [.invariant(wrappedParameter)])
    }

    /// A different expected type argument is still a real constraint: the
    /// inferred constructor argument must satisfy it.
    @Test func memberFunctionExpectedSupertypeStillRejectsIncompatibleArgument() throws {
        let ctx = try makeTestContext("""
        interface PS<E>
        class POS<E>(val a: E) : PS<E> {
            fun add(element: String): PS<E> = POS(element)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(!errors.isEmpty, "Expected POS<String> to be rejected for PS<E>")
    }

    /// Keep focused inference tests cheap; end-to-end diff cases own source
    /// injection as well, and the exact nested repro also runs both modes here.
    private func makeTestContext(_ source: String, fromSource: Bool = false) throws -> CompilationContext {
        if fromSource { return makeContextFromSource(source) }
        TestStdlibCache.shared.prepare()
        let library = try #require(CompilerOptions.defaultStdlibLibraryPath, "Shared stdlib artifact must be available")
        let manifest = URL(fileURLWithPath: library).appendingPathComponent("manifest.json")
        try #require(FileManager.default.fileExists(atPath: manifest.path), "Shared stdlib artifact must have a manifest")
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], stdlibLibraryPath: library)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }
}
#endif
