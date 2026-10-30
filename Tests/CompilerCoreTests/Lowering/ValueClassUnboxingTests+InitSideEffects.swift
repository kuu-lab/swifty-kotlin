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

    /// KUU-3830: `this(listOf(v))` lowers the collection literal through
    /// `kk_array_set(array, 0, v)` on a temporary container — not on `this`.
    /// The pass used to adopt that store's index as the underlying field
    /// offset, so the post-delegation extraction read box word 0 (the object
    /// header) instead of the stored payload and the value came back null.
    @Test
    func testSecondaryConstructorCollectionDelegationReadsUnderlyingField() throws {
        let source = """
        value class IC(val value: List<String>) {
            constructor(value: String) : this(listOf(value))
        }

        fun create(): String? = IC("abc").value.singleOrNull()
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let sema = try #require(ctx.sema)
        let module = try #require(ctx.kir)
        let interner = ctx.interner
        let arrayGet = interner.intern("kk_array_get_inbounds")

        let icSymbol = try #require(sema.symbols.allSymbols().first {
            $0.kind == .class && $0.name == interner.intern("IC")
        })
        let fieldOffsets = sema.symbols.nominalLayout(for: icSymbol.id)?.fieldOffsets ?? [:]
        let expectedOffset = try #require(
            fieldOffsets.values.sorted().first,
            "IC should have its single underlying field laid out"
        )

        // Only the caller's extraction read is inspected — stdlib functions
        // legitimately index real arrays at offset 0.
        var readOffsets: [Int64] = []
        for function in findAllKIRFunctions(in: module)
            where interner.resolve(function.name) == "create"
        {
            var literalByExpr: [KIRExprID: Int64] = [:]
            for instruction in function.body {
                if case let .constValue(result, value) = instruction,
                   case let .intLiteral(literal) = value
                {
                    literalByExpr[result] = literal
                }
            }
            for instruction in function.body {
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      callee == arrayGet, arguments.count == 2,
                      let offset = literalByExpr[arguments[1]]
                else { continue }
                readOffsets.append(offset)
            }
        }

        #expect(
            !readOffsets.isEmpty,
            "secondary-ctor construction must read the payload back out of the box"
        )
        #expect(
            !readOffsets.contains(0),
            "the extraction must not read the object header as the payload (KUU-3830)"
        )
        #expect(
            readOffsets.contains(Int64(expectedOffset)),
            "the extraction must read the real underlying field offset \(expectedOffset), got \(readOffsets)"
        )
    }
}
#endif
