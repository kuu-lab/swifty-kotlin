#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

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

    // KUU-4487: the `kotlin.Any.toString` vtable slot keeps the uniform raw
    // `(Int, Int*) -> Int` handle ABI (`kk_any_member_to_string`) even when
    // concrete subclasses override `toString`, so a `Base`-typed receiver
    // dispatches consistently and `kk_any_member_to_string` routes to the
    // override via `kk_object_register_any_to_string`. The raw
    // `kk_any_to_string_bridge_*` thunk must never be stored in the vtable
    // slot itself.
    @Test
    func toStringOverrideRegistersFlatImplementationInVtableSlot() throws {
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

        #expect(
            slotRegistrations.contains {
                sema.symbols.externalLinkName(for: $0.method) == "kk_any_member_to_string"
            },
            "the uniform raw kk_any_member_to_string entry must stay registered in the vtable slot"
        )

        let registeredFunctionNames = slotRegistrations.compactMap {
            module.arena.function(for: $0.method).map { interner.resolve($0.name) }
        }
        #expect(
            !registeredFunctionNames.contains { $0.hasPrefix("kk_any_to_string_bridge_") },
            "the raw Any-dispatch bridge must not be stored in the vtable slot: \(registeredFunctionNames)"
        )

        let anyBridgeRegistrations = findAllKIRFunctions(in: module).flatMap { function in
            function.body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
                return interner.resolve(callee)
            }
        }
        #expect(anyBridgeRegistrations.contains("kk_object_register_any_to_string"))
    }

    // A class that does not override `toString` keeps the runtime
    // `kotlin.Any.toString` entry registered directly. Direct `.toString()`
    // calls on such receivers never emit a vtable dispatch (the
    // `kk_any_member_to_string` fallback handles them), so the raw runtime
    // ABI is never reached through the flat-typed indirect call.
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

    // KUU-4487: explicit Any-member calls on a base-typed receiver must use
    // the kk_any_member_* bridges (the runtime override registry), never a
    // vtable slot. Subclass vtables do not share a consistent slot for
    // kotlin.Any members — nominals rooted at an empty-vtable superclass
    // (e.g. bundled-stdlib kotlinx.serialization.json.JsonElement) number
    // their own members from slot 0, so a slot resolved from Any's layout
    // indexes an unrelated method on the concrete receiver.
    @Test
    func anyMemberCallsOnBaseReceiverUseBridgeNotVtable() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        abstract class Base
        class Impl(val v: Int) : Base() {
            override fun toString(): String = "I$v"
            override fun hashCode(): Int = v
            override fun equals(other: Any?): Boolean = other is Impl && other.v == v
        }
        fun probeToString(b: Base): String = b.toString()
        fun probeHashCode(b: Base): Int = b.hashCode()
        fun probeEquals(b: Base, o: Any?): Boolean = b.equals(o)
        """, allowDefaultStdlibLibrary: true)
        try runToKIR(context)
        #expect(!context.diagnostics.hasError)
        let module = try #require(context.kir)
        let interner = context.interner

        for name in ["probeToString", "probeHashCode", "probeEquals"] {
            let body = try findKIRFunctionBody(named: name, in: module, interner: interner)
            let virtualCallees = extractVirtualCallees(from: body, interner: interner)
            #expect(
                !virtualCallees.contains { $0.hasPrefix("kk_any_member_") },
                "\(name) must not vtable-dispatch an Any member; virtualCallees: \(virtualCallees)"
            )
            let callees = extractCallees(from: body, interner: interner)
            #expect(
                callees.contains { $0.hasPrefix("kk_any_member_") },
                "\(name) must call the Any-member bridge directly; callees: \(callees)"
            )
        }
    }
}
#endif
