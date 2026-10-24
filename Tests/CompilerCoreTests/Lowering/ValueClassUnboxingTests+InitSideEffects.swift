#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct ValueClassUnboxingInitSideEffectTests {
    /// Whether any lowered function still calls a constructor (or its
    /// `$default` stub) belonging to a value class. Init-bearing value-class
    /// constructors must keep executing so their side effects survive.
    private func hasLiveValueClassConstructorCall(
        in module: KIRModule,
        ctx: CompilationContext
    ) throws -> Bool {
        let sema = try #require(ctx.sema)
        var stubToCtor: [SymbolID: SymbolID] = [:]
        for sym in sema.symbols.allSymbols() where sym.kind == .constructor {
            stubToCtor[SyntheticSymbolScheme.defaultStubSymbol(for: sym.id)] = sym.id
        }
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction,
                      let symbol
                else { continue }
                let ctorSymbol = stubToCtor[symbol] ?? symbol
                guard let sym = sema.symbols.symbol(ctorSymbol),
                      sym.kind == .constructor,
                      let parentID = sema.symbols.parentSymbol(for: ctorSymbol),
                      let parentSym = sema.symbols.symbol(parentID),
                      parentSym.flags.contains(.valueType)
                else { continue }
                return true
            }
        }
        return false
    }

    @Test
    func testInitBlockConstructorCallSurvivesUnboxing() throws {
        // KUU-3113: `Meter(42)` must still execute the init block — the pass
        // used to replace the constructor call with a bare payload copy,
        // dropping the `count += amount` side effect.
        let source = """
        var count = 0
        value class Meter(val amount: Int) {
            init { count += amount }
        }

        fun create(): Int {
            val m = Meter(42)
            return m.amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        #expect(
            module.executedLowerings.contains("ValueClassUnboxing"),
            "ValueClassUnboxing pass should have been recorded"
        )
        #expect(
            try hasLiveValueClassConstructorCall(in: module, ctx: ctx),
            "constructor with an init block must keep its call so side effects run"
        )
    }

    @Test
    func testTrivialConstructorStillElided() throws {
        let source = """
        value class Meter(val amount: Int)

        fun create(): Int {
            val m = Meter(42)
            return m.amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        #expect(
            try !hasLiveValueClassConstructorCall(in: module, ctx: ctx),
            "field-only constructor should still be rewritten to a copy"
        )
    }

    @Test
    func testDefaultArgumentConstructionDoesNotDangle() throws {
        // `Meter()` goes through `Meter$default`: the payload is not an
        // argument of the call, so eliding it used to leave an undefined read
        // (KIR verifier KSWIFTK-KIR-0003).
        let source = """
        var count = 0
        value class Meter(val amount: Int = 5) {
            init { count += amount }
        }

        fun create(): Int {
            val m = Meter()
            return m.amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let kirErrors = ctx.diagnostics.diagnostics.filter {
            $0.severity == .error && $0.message.contains("KIR verifier")
        }
        #expect(
            kirErrors.isEmpty,
            "default-arg value-class construction must not leave undefined reads: \(kirErrors.map(\.message))"
        )
        let module = try #require(ctx.kir)
        #expect(
            try hasLiveValueClassConstructorCall(in: module, ctx: ctx),
            "default-arg construction must keep the $default call"
        )
    }
}
#endif
