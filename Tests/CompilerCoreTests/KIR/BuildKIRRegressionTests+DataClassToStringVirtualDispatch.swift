#if canImport(Testing)
@testable import CompilerCore
import Testing
import TestStdlibCache
@testable import CompilerTestSupport

extension BuildKIRRegressionTests {
    /// `kotlin.Any.toString` slots found in the synthesized `toString` body of
    /// the named data class — the only dispatch slot a class-typed property's
    /// stringification may use. The synthesized body only exists after
    /// `LoweringPhase` (DataEnumSealedSynthesisPass), so callers must run
    /// `runToLowering`, not `runToKIR`.
    private func dataClassToStringVirtualSlots(
        of nominalName: String,
        in module: KIRModule,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> [Int64] {
        let toString = try #require(sema.symbols.lookupAll(fqName: [
            interner.intern(nominalName), interner.intern("toString"),
        ]).first { sema.symbols.symbol($0)?.kind == .function })
        let function = try #require(module.arena.function(for: toString))
        return function.body.compactMap { instruction -> Int64? in
            guard case let .virtualCall(_, _, _, _, _, _, _, dispatch) = instruction,
                  case let .vtable(slot) = dispatch
            else { return nil }
            return Int64(slot)
        }
    }

    /// The vtable slot `member` occupies in `nominalName`'s layout under its
    /// own symbol key — for an inherited Any member this is the shared Any
    /// slot; for a synthesized data-class member it is an orphan slot that is
    /// never registered per-object.
    private func memberVtableSlot(
        _ member: InternedString,
        of nominalName: String,
        sema: SemaModule,
        interner: StringInterner
    ) throws -> Int64 {
        let memberSymbol = try #require(sema.symbols.lookupAll(fqName: [
            interner.intern(nominalName), member,
        ]).first { sema.symbols.symbol($0)?.kind == .function })
        let nominal = try #require(sema.symbols.lookup(fqName: [interner.intern(nominalName)]))
        let slot = try #require(sema.symbols.nominalLayout(for: nominal)?.vtableSlots[memberSymbol])
        return Int64(slot)
    }

    private func anyToStringSlot(
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

    // KUU-3110: a data class property typed as a base class must stringify
    // through the `kotlin.Any.toString` vtable slot so the receiver's
    // most-derived override runs.
    @Test
    func dataClassToStringUsesAnyVtableSlotForBaseTypedProperty() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        open class Base {
            override fun toString(): String = "base"
        }
        class Child : Base() {
            override fun toString(): String = "child"
        }
        data class Holder(val value: Base)
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)
        let interner = context.interner

        let anySlot = try anyToStringSlot(of: "Base", sema: sema, interner: interner)
        let virtualSlots = try dataClassToStringVirtualSlots(
            of: "Holder", in: module, sema: sema, interner: interner
        )
        #expect(virtualSlots == [anySlot])
    }

    // A final data class's own synthesized `toString` occupies an orphan
    // vtable slot that is never registered per-object, so a property typed as
    // that data class must still dispatch through the inherited
    // `kotlin.Any.toString` slot.
    @Test
    func dataClassToStringAvoidsOrphanSlotForDataClassProperty() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        data class Inner(val x: Int)
        data class Holder(val inner: Inner)
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)
        let interner = context.interner

        let anySlot = try anyToStringSlot(of: "Inner", sema: sema, interner: interner)
        let orphanSlot = try memberVtableSlot(
            interner.intern("toString"), of: "Inner", sema: sema, interner: interner
        )
        let virtualSlots = try dataClassToStringVirtualSlots(
            of: "Holder", in: module, sema: sema, interner: interner
        )
        #expect(orphanSlot != anySlot)
        #expect(virtualSlots == [anySlot])
    }

    // A property typed as an interface has no `kotlin.Any.toString` vtable
    // slot to dispatch through — the synthesized body must fall back to
    // `kk_any_to_string` rather than emitting a virtualCall on an
    // interface-owned slot that is never registered.
    @Test
    func dataClassToStringFallsBackForInterfaceTypedProperty() throws {
        TestStdlibCache.shared.prepare()
        let context = makeContextFromSource("""
        interface Named {
            override fun toString(): String
        }
        data class Holder(val value: Named)
        """, allowDefaultStdlibLibrary: true)
        try runToLowering(context)
        #expect(!context.diagnostics.hasError)
        let sema = try #require(context.sema)
        let module = try #require(context.kir)
        let interner = context.interner

        let virtualSlots = try dataClassToStringVirtualSlots(
            of: "Holder", in: module, sema: sema, interner: interner
        )
        #expect(virtualSlots.isEmpty)
    }
}
#endif
