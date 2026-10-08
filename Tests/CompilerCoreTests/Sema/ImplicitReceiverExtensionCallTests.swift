#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite struct ImplicitReceiverExtensionCallTests {
    @Test(arguments: ["launch", "async"])
    func suspendReceiverLambdaArgumentResolvesInsideExtension(name: String) throws {
        let ctx = makeContextFromSource("""
        interface CC
        interface Job
        interface CScope { val ctx: CC }
        fun CScope.\(name)(context: CC, block: suspend CScope.() -> Unit): Job = TODO()

        fun CScope.reader(coroutineContext: CC) {
            val a = \(name)(coroutineContext) { val context: CC = ctx }
            val b = this.\(name)(coroutineContext) { val context: CC = ctx }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: name, in: ast, interner: ctx.interner))
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName == [ctx.interner.intern(name)])
        let lambda = try #require(firstExprID(in: ast) { _, expr in
            if case .lambdaLiteral = expr { return true }
            return false
        })
        #expect(!sema.bindings.isCoroutineLauncherLambdaExpr(lambda))
    }

    @Test func noArgumentExtensionCallBindsImplicitReceiver() throws {
        let ctx = makeContextFromSource("""
        interface Source
        fun Source.readCodePointValue(): Int = 42
        fun Source.readUtf8ExactCharacters(): Int = readCodePointValue()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let call = try #require(nameRefCallExprID(named: "readCodePointValue", in: ast, interner: ctx.interner))
        #expect(sema.bindings.implicitReceiverMemberNames[call] != nil)
    }

    /// KUU-1451: bundled "property-style" members are declared as
    /// zero-argument extension functions (`List.lastIndex`,
    /// `Collection.indices`, `Array.lastIndex`, ...). A bare read on a scope
    /// lambda's implicit receiver must bind the receiver-matching overload as
    /// a call — not the raw function symbol — so KIR materializes `this` as
    /// the callee's receiver argument.
    @Test func bareSyntheticMemberPropertyBindsImplicitReceiverCall() throws {
        let source = """
        fun main() {
            val l = listOf(1, 2, 3)
            println(l.run { lastIndex })
            with(l) { println(indices) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let listFQName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("List"),
            ]
            for member in ["lastIndex", "indices"] {
                // AST normalization leaves a discarded `.nameRef` twin at the
                // same source range; the live expr is the one Sema typed.
                let refs = allExprIDs(in: ast, path: path, ctx: ctx) { exprID, expr in
                    guard case let .nameRef(name, _) = expr else { return false }
                    return ctx.interner.resolve(name) == member
                        && sema.bindings.exprType(for: exprID) != nil
                }
                #expect(refs.count == 1)
                let ref = try #require(refs.first)
                #expect(sema.bindings.implicitReceiverMemberNames[ref] != nil)
                let binding = try #require(sema.bindings.callBinding(for: ref))
                let callee = try #require(sema.symbols.symbol(binding.chosenCallee))
                #expect(callee.fqName == [
                    ctx.interner.intern("kotlin"),
                    ctx.interner.intern("collections"),
                    ctx.interner.intern(member),
                ])
                // The List receiver overload must win over the Array/Collection ones.
                let signature = try #require(sema.symbols.functionSignature(for: binding.chosenCallee))
                let receiver = try #require(signature.receiverType)
                guard case let .classType(receiverClass) = sema.types.kind(of: receiver) else {
                    Issue.record("expected classType receiver for \(member), got \(receiver)")
                    continue
                }
                #expect(sema.symbols.symbol(receiverClass.classSymbol)?.fqName == listFQName)
            }
        }
    }

    /// KUU-1451 contract limit: the property-style facade is a bundled-stdlib
    /// convention. A bare read of an ordinary member function on the implicit
    /// receiver must not be bound as a call — Kotlin requires `m()`
    /// invocation syntax (`c.run { m }` is a compiler error on the JVM).
    /// The explicit `c.m` acceptance is a separate pre-existing deviation.
    @Test func bareMemberFunctionDoesNotBindImplicitReceiverCall() throws {
        let source = """
        class C { fun m(): Int = 7 }
        fun main() {
            val c = C()
            c.run { m }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let refs = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                guard case let .nameRef(name, _) = expr else { return false }
                return name == ctx.interner.intern("m")
            }
            // `m` must not resolve as an implicit-receiver member call. It
            // may be entirely unresolved (kotlinc rejects this program), but
            // no form of the expr may carry a call binding.
            #expect(!refs.isEmpty)
            for ref in refs {
                #expect(sema.bindings.implicitReceiverMemberNames[ref] == nil)
                #expect(sema.bindings.callBinding(for: ref) == nil)
            }
        }
    }

    /// KUU-1451 contract limit: bundled provenance alone is not a property
    /// facade — `kotlin.collections.first`/`count` are ordinary zero-argument
    /// functions in the same package and index as `lastIndex`. kotlinc
    /// rejects `l.run { first }` with "function invocation 'first()'
    /// expected", so they must not bind implicit-receiver calls.
    @Test func bareBundledOrdinaryFunctionDoesNotBindImplicitReceiverCall() throws {
        let source = """
        fun main() {
            val l = listOf(1, 2, 3)
            l.run { first }
            l.run { count }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for member in ["first", "count"] {
                let refs = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
                    guard case let .nameRef(name, _) = expr else { return false }
                    return ctx.interner.resolve(name) == member
                }
                #expect(!refs.isEmpty, "expected a \(member) nameRef in the fixture")
                for ref in refs {
                    #expect(sema.bindings.implicitReceiverMemberNames[ref] == nil)
                    #expect(sema.bindings.callBinding(for: ref) == nil)
                }
            }
        }
    }

    @Test func incompatibleImplicitReceiverStillRejectsExtension() throws {
        let ctx = makeContextFromSource("""
        interface Source
        interface Other
        fun Source.readCodePointValue(): Int = 42
        fun Other.readUtf8ExactCharacters(): Int = readCodePointValue()
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }
}
#endif
