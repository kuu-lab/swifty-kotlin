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
