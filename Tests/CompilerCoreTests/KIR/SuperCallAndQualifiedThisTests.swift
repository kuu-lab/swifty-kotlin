#if canImport(Testing)
@testable import CompilerCore
import Testing

private func extractSuperCallFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [(callee: String, isSuperCall: Bool, qualifiedSuperType: SymbolID?)] {
    body.compactMap { instruction -> (callee: String, isSuperCall: Bool, qualifiedSuperType: SymbolID?)? in
        guard case let .call(_, callee, _, _, _, _, isSuperCall, qualifiedSuperType) = instruction else {
            return nil
        }
        return (interner.resolve(callee), isSuperCall, qualifiedSuperType)
    }
}

private func findAllKIRFunctionBodies(
    named name: String,
    in module: KIRModule,
    interner: StringInterner
) -> [[KIRInstruction]] {
    findAllKIRFunctions(in: module).compactMap { function -> [KIRInstruction]? in
        return interner.resolve(function.name) == name ? function.body : nil
    }
}

private func extractSuperCallFlagsAcrossOverrides(
    named name: String,
    in module: KIRModule,
    interner: StringInterner
) -> [(callee: String, isSuperCall: Bool)] {
    findAllKIRFunctionBodies(named: name, in: module, interner: interner)
        .flatMap { extractSuperCallFlags(from: $0, interner: interner) }
        .map { ($0.callee, $0.isSuperCall) }
}

@Suite
struct SuperCallAndQualifiedThisTests {

    @Test(arguments: [false, true])
    func testQualifiedClassAndInterfaceSuperCalls(fullyLowered: Bool) throws {
        let ctx = makeContextFromSource("""
        open class A1 { open fun f(): Int = 1 }
        interface B1 { fun f(): Int = 2 }
        class C1 : A1(), B1 {
            override fun f(): Int = super<A1>.f() + super<B1>.f()
        }
        """)
        if fullyLowered {
            try runToLowering(ctx)
        } else {
            try runToKIR(ctx)
        }
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let flags = findAllKIRFunctionBodies(named: "f", in: module, interner: ctx.interner)
            .flatMap { extractSuperCallFlags(from: $0, interner: ctx.interner) }
            .filter { $0.callee == "f" && $0.isSuperCall }
        let qualifiers = flags.compactMap { flag in
            flag.qualifiedSuperType.flatMap { sema.symbols.symbol($0) }
                .map { ctx.interner.resolve($0.name) }
        }
        #expect(flags.count == 2)
        #expect(Set(qualifiers) == ["A1", "B1"])
        for body in findAllKIRFunctionBodies(named: "f", in: module, interner: ctx.interner) {
            for instruction in body {
                guard case let .call(symbol, _, _, _, _, _, true, qualifier?) = instruction else { continue }
                let callee = try #require(symbol)
                #expect(sema.symbols.parentSymbol(for: callee) == qualifier)
            }
        }
    }

    @Test func testQualifiedClassSuperCallWithArgument() throws {
        let ctx = makeContextFromSource("""
        open class Base { open fun f(x: Int): Int = x + 1 }
        class Child : Base() {
            override fun f(x: Int): Int = super<Base>.f(x) + 10
        }
        """)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        let module = try #require(ctx.kir)
        let sema = try #require(ctx.sema)
        let calls = findAllKIRFunctionBodies(named: "f", in: module, interner: ctx.interner)
            .flatMap { extractSuperCallFlags(from: $0, interner: ctx.interner) }
        let superCall = try #require(calls.first { $0.isSuperCall })
        let qualifier = try #require(superCall.qualifiedSuperType)
        let qualifierSymbol = try #require(sema.symbols.symbol(qualifier))
        #expect(ctx.interner.resolve(qualifierSymbol.name) == "Base")
    }

    @Test(arguments: ["Root", "Other", "Missing"])
    func testQualifiedSuperRejectsNonDirectSupertype(qualifier: String) throws {
        let ctx = makeContextFromSource("""
        open class Root { open fun f(): Int = 1 }
        open class Base : Root()
        open class Other { open fun f(): Int = 2 }
        class Child : Base() {
            override fun f(): Int = super<\(qualifier)>.f()
        }
        """)
        try runSema(ctx)
        assertHasDiagnostic("KSWIFTK-SEMA-0054", in: ctx)
    }

    @Test func testSuperCallProducesIsSuperCallTrueInKIR() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!(ctx.diagnostics.hasError),
                       "Expected super call program to compile without sema errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")

        let module = try #require(ctx.kir)
        // Both Base.greet and Child.greet exist; search across all overrides
        let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)

        // The overridden greet() should contain a call to greet with isSuperCall=true
        let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
        #expect(superGreetCall != nil, "Expected a call to 'greet' with isSuperCall=true in Child.greet() body, got: \(flags)")
    }

    @Test func testRegularMemberCallHasIsSuperCallFalse() throws {
        let source = """
        class Greeter {
            fun greet(): String = "hello"
            fun callGreet(): String = this.greet()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        #expect(!(ctx.diagnostics.hasError),
                       "Expected regular call program to compile without errors.")

        let module = try #require(ctx.kir)
        let body = try findKIRFunctionBody(named: "callGreet", in: module, interner: ctx.interner)
        let flags = extractSuperCallFlags(from: body, interner: ctx.interner)

        let greetCall = flags.first { $0.callee == "greet" }
        #expect(greetCall != nil, "Expected a call to 'greet' in callGreet() body.")
        #expect(!(greetCall?.isSuperCall ?? true),
                       "Expected this.greet() to have isSuperCall=false, got: \(flags)")
    }

    @Test func testIsSuperCallSurvivesFullLoweringPipeline() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        #expect(!(ctx.diagnostics.hasError),
                       "Expected super call program to compile and lower without errors.")

        let module = try #require(ctx.kir)
        // Search across all overrides of 'greet'
        let flags = extractSuperCallFlagsAcrossOverrides(named: "greet", in: module, interner: ctx.interner)

        // After full lowering, the super call should still have isSuperCall=true
        let superGreetCall = flags.first { $0.callee == "greet" && $0.isSuperCall }
        #expect(superGreetCall != nil,
                        "Expected isSuperCall=true to survive full lowering pipeline, got: \(flags)")
    }

    @Test func testIsSuperCallPreservedThroughABILowering() throws {
        // Use Any parameter to force ABI boxing pass to rewrite the call
        let source = """
        open class Base {
            open fun process(x: Any): Any = x
        }
        class Child : Base() {
            override fun process(x: Any): Any = super.process(x)
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        #expect(!(ctx.diagnostics.hasError),
                       "Expected ABI boxing super call to compile and lower without errors.")

        let module = try #require(ctx.kir)
        // Search across all overrides of 'process'
        let flags = extractSuperCallFlagsAcrossOverrides(named: "process", in: module, interner: ctx.interner)

        let processCall = flags.first { $0.callee == "process" && $0.isSuperCall }
        #expect(processCall != nil,
                        "Expected isSuperCall=true to survive ABI lowering with boxing, got: \(flags)")
    }

    @Test func testQualifiedThisResolvesToOuterClassType() throws {
        let source = """
        class Outer {
            fun getOuter(): Outer = this
            inner class Inner {
                fun getOuter(): Outer = this@Outer
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Should compile without errors — this@Outer resolves to Outer type
        let hasError = ctx.diagnostics.diagnostics.contains { $0.severity == .error }
        #expect(!(hasError),
                       "Expected this@Outer in nested class to resolve without errors, got: \(ctx.diagnostics.diagnostics.map(\.message))")
    }

    @Test func testUnresolvedQualifiedThisEmitsDiagnostic() throws {
        let source = """
        class Outer {
            class Inner {
                fun bad(): Int = this@NonExistent
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-0053", in: ctx)
    }

    // MARK: - `this` inside lambdas with receiver

    private static let nestedReceiverLambdaSource = """
    class A(val v: Int)
    class B(val w: Int)
    fun <T> withA(a: A, f: A.() -> T): T = a.f()
    fun <T> withB(b: B, f: B.() -> T): T = b.f()
    fun String.ext(): Int = withB(B(2)) { this.w + this@ext.length }
    fun main() {
        println(withA(A(1)) { withB(B(2)) { this@withA.v + this.w } })
    }
    """

    /// Lambda literals in source order as `(exprID, label)`.
    private func lambdaLiterals(in ctx: CompilationContext) throws -> [(id: ExprID, label: String?)] {
        let ast = try #require(ctx.ast)
        return ast.arena.exprs.enumerated().compactMap { index, expr in
            guard case let .lambdaLiteral(_, _, label, _) = expr else { return nil }
            return (ExprID(rawValue: Int32(index)), label.map { ctx.interner.resolve($0) })
        }
    }

    @Test func testCalleeLabelQualifiedThisResolvesInReceiverLambda() throws {
        let ctx = makeContextFromSource(Self.nestedReceiverLambdaSource)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message)
        #expect(errors.isEmpty, "this@withA / this.w / this@ext inside receiver lambdas must type-check, got: \(errors)")
    }

    @Test func testNestedCalleeLabelThisBindsOuterLambdaReceiverAndIsCaptured() throws {
        let ctx = makeContextFromSource(Self.nestedReceiverLambdaSource)
        try runSema(ctx)
        let sema = try #require(ctx.sema)
        let lambdas = try lambdaLiterals(in: ctx)
        let outer = try #require(lambdas.first { $0.label == "withA" && $0.id.rawValue < 1000 })
        let outerReceiver = SyntheticSymbolScheme.lambdaReceiverSymbol(for: outer.id)
        let innerLambdas = lambdas.filter { $0.label == "withB" && $0.id.rawValue < 1000 }
        // `this@withA` must be bound to the OUTER lambda's receiver symbol (never the inner one)...
        let ast = try #require(ctx.ast)
        let qualified = ast.arena.exprs.enumerated().compactMap { index, expr -> ExprID? in
            if case let .thisRef(label?, _) = expr, ctx.interner.resolve(label) == "withA" {
                return ExprID(rawValue: Int32(index))
            }
            return nil
        }
        #expect(qualified.contains { sema.bindings.identifierSymbol(for: $0) == outerReceiver })
        // ...and a withB lambda must capture it so KIR reads the outer receiver value,
        // while no lambda ever captures its own receiver symbol.
        let captureSets = innerLambdas.map { (lambda: $0, symbols: sema.bindings.captureSymbolsByExpr[$0.id] ?? []) }
        #expect(captureSets.contains { $0.symbols.contains(outerReceiver) }, "captures: \(captureSets.map(\.symbols))")
        for entry in captureSets {
            #expect(!entry.symbols.contains(SyntheticSymbolScheme.lambdaReceiverSymbol(for: entry.lambda.id)))
        }
    }

    @Test func testExplicitThisInReceiverLambdaUsesLambdaReceiverNotEnclosingExtension() throws {
        let ctx = makeContextFromSource("""
        class W(val w: Int)
        fun <T> withW(w: W, f: W.() -> T): T = w.f()
        fun String.ext(): Int = withW(W(3)) { this.w }
        class C { fun f(): Int = withW(W(4)) { this.w } }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.message)
        #expect(errors.isEmpty, "explicit `this` must be the lambda receiver W, got: \(errors)")
    }

    @Test func testNestedReceiverLambdaLowersToKIRWithoutErrors() throws {
        let ctx = makeContextFromSource(Self.nestedReceiverLambdaSource)
        try runToKIR(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics.map(\.message))")
        _ = try #require(ctx.kir)
    }

    @Test func testKIRDumpFormatIncludesSuperTag() throws {
        let source = """
        open class Base {
            open fun greet(): String = "hello"
        }
        class Child : Base() {
            override fun greet(): String = super.greet()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)

        // The full dump should include 'super=1' for the super.greet() call
        let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        #expect(dumpOutput.contains("super=1"),
                      "Expected KIR dump to contain 'super=1' for super call, got:\n\(dumpOutput)")
    }

    @Test func testKIRDumpDoesNotIncludeSuperTagForRegularCalls() throws {
        let source = """
        fun greet(): String = "hello"
        fun main() = greet()
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)
        let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        #expect(!(dumpOutput.contains("super=1")),
                       "Regular call dump should not contain 'super=1', got:\n\(dumpOutput)")
    }

    @Test func testKIRDumpFormatIncludesQualifiedSuperTag() throws {
        let source = """
        interface Left {
            fun default1(): String = "left"
        }
        interface Right {
            fun default1(): String = "right"
        }
        class Child : Left, Right {
            fun callLeft(): String = super<Left>.default1()
        }
        """
        let ctx = makeContextFromSource(source)
        try runToKIR(ctx)

        let module = try #require(ctx.kir)

        // The full dump should include 'qualifiedSuper=' for the super<Left>.default1() call
        let dumpOutput = module.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        #expect(dumpOutput.contains("qualifiedSuper="),
                      "Expected KIR dump to contain 'qualifiedSuper=' for qualified super call, got:\n\(dumpOutput)")
    }
}
#endif
