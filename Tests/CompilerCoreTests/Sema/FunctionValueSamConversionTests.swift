#if canImport(Testing)
@testable import CompilerCore
import Testing
import Foundation

@Suite
struct FunctionValueSamConversionTests {
    private func makeSamContext(_ source: String) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test func issueReproducerSelectsMembersAndBindsConversions() throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run(n: Int): Int }
        interface S { fun choose(block: Action): Int }
        fun choose(block: (Int) -> Int): String = "outer"
        fun S.read(action: (Int) -> Int): Int = choose(action)
        fun explicit(s: S, action: (Int) -> Int): Int = s.choose(action)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        let sema = try #require(ctx.sema)
        let member = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("S"), ctx.interner.intern("choose")]))
        #expect(sema.bindings.callBindings.values.filter { $0.chosenCallee == member }.count == 2)
        #expect(sema.bindings.samConversionExprs.count == 2)
        for expr in sema.bindings.samConversionExprs {
            #expect(sema.bindings.samInterfaceType(for: expr) != nil)
            #expect(sema.bindings.samUnderlyingFunctionType(for: expr) != nil)
            guard let type = sema.bindings.exprType(for: expr) else { Issue.record("Missing source type"); continue }
            guard case .functionType = sema.types.kind(of: type) else { Issue.record("Lost source function type"); continue }
        }
    }

    @Test(arguments: [
        "fun test(action: (Int) -> Int): Int = use(action)",
        "fun test(action: (Int) -> Int): Int = use(block = action)",
        "fun test(action: (Int) -> Int): Int { val local = action; return use(local) }",
        "fun make(): (Int) -> Int = { it }\nfun test(action: (Int) -> Int): Int = use(make())",
    ])
    func ordinaryCallsAcceptFunctionValues(test: String) throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run(n: Int): Int }
        fun use(block: Action): Int = block.run(3)
        \(test)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
        #expect(try #require(ctx.sema).bindings.samConversionExprs.count == 1)
    }

    @Test func nonSuspendFunctionValuesAdaptToSuspendSam() throws {
        let ctx = makeSamContext("""
        fun interface FunInterface {
            suspend operator fun invoke()
        }
        fun func(f: FunInterface) { }

        fun box(): String {
            val lambda: () -> Unit = { }
            func(f = lambda)
            func(lambda)
            func { }
            return "OK"
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let sema = try #require(ctx.sema)
        #expect(sema.bindings.samConversionExprs.count >= 2)
        for expr in sema.bindings.samConversionExprs {
            guard let underlyingType = sema.bindings.samUnderlyingFunctionType(for: expr),
                  case let .functionType(functionType) = sema.types.kind(of: underlyingType)
            else {
                Issue.record("Missing suspend SAM function type")
                continue
            }
            #expect(functionType.isSuspend)
        }
    }

    @Test func intersectionBoundFunctionValuesAdaptToMatchingSam() throws {
        let ctx = makeSamContext("""
        fun interface KRunnable { fun invoke() }
        fun interface KBoolean { fun invoke(b: Boolean) }
        fun useFunInterface(fn: KRunnable) { fn.invoke() }
        fun useFunInterfacePredicate(fn: KBoolean) { fn.invoke(true) }
        fun <T> testIntersection(x: T) where T : () -> Unit, T : (Boolean) -> Unit {
            useFunInterface(x)
            useFunInterfacePredicate(x)
        }
        object Test : () -> Unit, (Boolean) -> Unit {
            override fun invoke() {}
            override fun invoke(p1: Boolean) {}
        }
        fun main() { testIntersection(Test) }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Each function-type bound must adapt to its matching SAM: \(errors)")
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.samConversionExprs.count == 2)
        for expr in sema.bindings.samConversionExprs {
            #expect(sema.bindings.samInterfaceType(for: expr) != nil)
            #expect(sema.bindings.samUnderlyingFunctionType(for: expr) != nil)
        }
    }

    @Test func suspendSamFunctionValuesPreserveReceiverAndContextShape() throws {
        let ctx = makeSamContext("""
        fun interface SuspendIntAction { suspend fun run(value: Int) }
        fun interface ContextSuspendAction { context(String) suspend fun run() }
        fun takeInt(action: SuspendIntAction) {}
        fun takeContext(action: ContextSuspendAction) {}

        fun acceptsReceiver(action: Int.() -> Unit) { takeInt(action) }
        fun acceptsMatchingContext(action: context(String) () -> Unit) { takeContext(action) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        #expect(try #require(ctx.sema).bindings.samConversionExprs.count == 2)
    }

    @Test(arguments: [
        "fun invalid(action: suspend () -> Unit) { takePlain(action) }",
        "fun invalid(action: () -> Int) { takeSuspend(action) }",
        "fun invalid(action: () -> Unit) { takeInt(action) }",
        "fun invalid(action: (String) -> Unit) { takeInt(action) }",
        "fun invalid(action: context(Int) () -> Unit) { takeContext(action) }",
    ])
    func suspendSamFunctionValuesRejectIncompatibleShapes(declaration: String) throws {
        let ctx = makeSamContext("""
        fun interface PlainAction { fun run() }
        fun interface SuspendAction { suspend fun run() }
        fun interface SuspendIntAction { suspend fun run(value: Int) }
        fun interface ContextSuspendAction { context(String) suspend fun run() }
        fun takePlain(action: PlainAction) {}
        fun takeSuspend(action: SuspendAction) {}
        fun takeInt(action: SuspendIntAction) {}
        fun takeContext(action: ContextSuspendAction) {}
        \(declaration)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(try #require(ctx.sema).bindings.samConversionExprs.isEmpty)
    }

    @Test func nullableFunctionValuesConvertToNullableSam() throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run() }
        fun take(action: Action?) {}
        fun test(action: (() -> Unit)?): Unit = take(action)
        fun testNull(): Unit {
            val action: (() -> Unit)? = null
            take(action)
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")

        let sema = try #require(ctx.sema)
        #expect(sema.bindings.samConversionExprs.count == 2)
        for expr in sema.bindings.samConversionExprs {
            guard let sourceType = sema.bindings.exprType(for: expr) else {
                Issue.record("Missing source function type")
                continue
            }
            #expect(sema.types.nullability(of: sourceType) == .nullable)
            guard let interfaceType = sema.bindings.samInterfaceType(for: expr) else {
                Issue.record("Missing target SAM interface type")
                continue
            }
            #expect(sema.types.nullability(of: interfaceType) == .nullable)
            guard let underlyingType = sema.bindings.samUnderlyingFunctionType(for: expr) else {
                Issue.record("Missing underlying SAM function type")
                continue
            }
            #expect(sema.types.nullability(of: underlyingType) == .nonNull)
        }
    }

    @Test func nullableFunctionValuesRequireNullableCompatibleSamTarget() throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run() }
        fun interface TypedAction { fun run(n: Int): Int }
        fun takeNonNull(action: Action) {}
        fun takeTyped(action: TypedAction?) {}
        fun invalidNullability(action: (() -> Unit)?) = takeNonNull(action)
        fun invalidSignature(action: (() -> Unit)?) = takeTyped(action)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(try #require(ctx.sema).bindings.samConversionExprs.isEmpty)
    }

    @Test(arguments: ["(String) -> Int", "(Int) -> String", "() -> Int", "((Int) -> Int)?", "suspend (Int) -> Int"])
    func incompatibleFunctionValuesAreRejected(type: String) throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run(n: Int): Int }
        interface S { fun choose(block: Action): Int }
        fun test(s: S, action: \(type)): Int = s.choose(action)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(try #require(ctx.sema).bindings.samConversionExprs.isEmpty)
    }

    @Test func genericSamInfersTypeArgumentFromFunctionValue() throws {
        let ctx = makeSamContext("""
        fun interface Action<T> { fun run(n: T): T }
        fun <T> use(block: Action<T>): T = block.run(3 as T)
        fun test(action: (Int) -> Int): Int = use(action)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        #expect(try #require(ctx.sema).bindings.samConversionExprs.count == 1)
    }

    @Test func ordinaryFunctionOverloadWinsWithoutConversion() throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run(n: Int): Int }
        fun use(block: Action): Int = 42
        fun use(block: (Int) -> Int): Int = block(3)
        fun test(action: (Int) -> Int): Int = use(action)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
        #expect(try #require(ctx.sema).bindings.samConversionExprs.isEmpty)
    }

    @Test func samAdaptationDoesNotMakeAssignmentOrOrdinaryInterfaceValid() throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run(n: Int): Int }
        interface Ordinary { fun run(n: Int): Int }
        fun use(block: Ordinary): Int = block.run(3)
        fun test(action: (Int) -> Int) {
            val invalid: Action = action
            use(action)
        }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError)
        #expect(try #require(ctx.sema).bindings.samConversionExprs.isEmpty)
    }

    @Test func samOverloadWithCallableReferenceStillTypeChecks() throws {
        let ctx = makeSamContext("""
        fun interface Action { fun run(n: Int): Int }
        fun use(block: Action): Int = block.run(3)
        fun use(value: Int): Int = value
        fun double(value: Int): Int = value * 2
        fun test(): Int = use(::double)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError)
    }
}
#endif
