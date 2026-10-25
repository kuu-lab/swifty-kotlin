#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache

extension BuildKIRRegressionTests {
    /// All `kk_object_register_vtable_method` registrations in the module:
    /// (slot, methodSymbol) pairs resolved from their constant expressions.
    private func allVtableMethodRegistrations(
        in module: KIRModule,
        interner: StringInterner
    ) -> [(slot: Int64, method: SymbolID)] {
        findAllKIRFunctions(in: module).flatMap { function in
            var intConstants: [KIRExprID: Int64] = [:]
            var symbolConstants: [KIRExprID: SymbolID] = [:]
            for instruction in function.body {
                if case let .constValue(result, .intLiteral(value)) = instruction {
                    intConstants[result] = value
                }
                if case let .constValue(result, .symbolRef(symbol)) = instruction {
                    symbolConstants[result] = symbol
                }
            }
            return function.body.compactMap { instruction -> (slot: Int64, method: SymbolID)? in
                guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                      interner.resolve(callee) == "kk_object_register_vtable_method",
                      arguments.count == 3,
                      let slot = intConstants[arguments[1]],
                      let method = symbolConstants[arguments[2]]
                else { return nil }
                return (slot, method)
            }
        }
    }

    /// The `kotlin.Any.toString` vtable slot only exists when the stdlib is
    /// imported from the `.kklib` artifact: the source-injected `kotlin.Any`
    /// deliberately keeps an empty vtable, so this KUU-3111 regression test
    /// must run against `allowDefaultStdlibLibrary`.
    private func anyToStringVtableSlot(
        of nominalName: String,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> Int64 {
        let anyToString = try #require(sema.symbols.lookupAll(fqName: [
            interner.intern("kotlin"), interner.intern("Any"), interner.intern("toString"),
        ]).first { sema.symbols.symbol($0)?.kind == .function })
        let nominal = try #require(sema.symbols.lookup(fqName: [interner.intern(nominalName)]))
        let slot = try #require(sema.symbols.nominalLayout(for: nominal)?.vtableSlots[anyToString])
        return Int64(slot)
    }

    // KUU-3111: the `kotlin.Any.toString` vtable slot carries the runtime's
    // raw (Int) -> Int string-handle ABI, so a Kotlin override returning the
    // flat String aggregate must be registered through the generated raw
    // bridge — never as the implementation's own function pointer.
    @Test
    func toStringOverrideRegistersRawBridgeInVtableSlot() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        open class Base {
            override fun toString(): String = "base"
        }
        class Child : Base() {
            override fun toString(): String = "child"
        }
        fun probe(): Base {
            return Child()
        }
        """, allowDefaultStdlibLibrary: true)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)
        let interner = context.interner

        let slot = try anyToStringVtableSlot(of: "Child", sema: sema, interner: interner)
        let slotRegistrations = allVtableMethodRegistrations(in: module, interner: interner)
            .filter { $0.slot == slot }
        #expect(!slotRegistrations.isEmpty)

        let aggregateImplementations = Set(
            ["Base", "Child"].flatMap { owner in
                sema.symbols.lookupAll(fqName: [
                    interner.intern(owner), interner.intern("toString"),
                ]).filter { sema.symbols.symbol($0)?.kind == .function }
            }
        )
        for registration in slotRegistrations {
            #expect(
                !aggregateImplementations.contains(registration.method),
                "aggregate-ABI toString must not be stored in the raw-ABI slot"
            )
        }

        let bridgeNames = slotRegistrations.compactMap {
            module.arena.function(for: $0.method).map { interner.resolve($0.name) }
        }
        #expect(
            bridgeNames.contains { $0.hasPrefix("kk_any_to_string_bridge_") },
            "expected the raw string-handle bridge among \(bridgeNames)"
        )
        if let bridgeSymbol = slotRegistrations.first(where: {
            module.arena.function(for: $0.method).map {
                interner.resolve($0.name).hasPrefix("kk_any_to_string_bridge_")
            } == true
        })?.method,
           let bridge = module.arena.function(for: bridgeSymbol)
        {
            #expect(bridge.returnType == sema.types.intType)
        }
    }

    // A class that does not override `toString` keeps the runtime
    // `kotlin.Any.toString` entry registered directly — its ABI is already
    // the raw one the slot contract expects.
    @Test
    func inheritedToStringKeepsRuntimeSymbolInVtableSlot() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        open class Base
        fun probe(): Base {
            return Base()
        }
        """, allowDefaultStdlibLibrary: true)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)

        let slot = try anyToStringVtableSlot(of: "Base", sema: sema, interner: context.interner)
        let slotRegistrations = allVtableMethodRegistrations(in: module, interner: context.interner)
            .filter { $0.slot == slot }
        #expect(!slotRegistrations.isEmpty)
        #expect(
            slotRegistrations.contains {
                sema.symbols.externalLinkName(for: $0.method) == "kk_any_member_to_string"
            },
            "the runtime Any.toString member should stay registered for the slot"
        )
    }
}
#endif
