@testable import CompilerCore
import Foundation
import Testing

/// KUU-545: a bundled `external fun` extension whose receiver is an interface
/// type must not corrupt that interface's method-slot layout. The KSP-443
/// owner+name lookup alias created for such a function is a lookup shim, not
/// a real member — counting it in `orderedOwnMethods` inflated `vtableSize`,
/// which shifted `CharSequence.length`'s itable getter slot off the fixed slot
/// the runtime registers for String objects (`KSWIFTK-RUNTIME-0001`).
@Suite
struct ExtensionMemberAliasLayoutTests {
    /// Mirrors the KUU-545 trigger: an internal external extension declared on
    /// `CharSequence` that is never called, plus a `StringBuilder`-receiver
    /// control for the nominal-class case.
    private static let probeSource = """
    package kotlin.text

    import kotlin.internal.KsSymbolName

    @KsSymbolName("__kk_kuu545_iface_probe")
    internal external fun CharSequence.__kk_kuu545_iface_probe(): Int

    @KsSymbolName("__kk_kuu545_string_probe")
    internal external fun StringBuilder.__kk_kuu545_string_probe(): Int
    """

    private func compileWithBundledProbe() throws -> (sema: SemaModule, interner: StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}\n") { path in
            let ctx = makeCompilationContext(inputs: [path])
            _ = ctx.sourceManager.addFile(
                path: "__bundled_kuu545_probe.kt",
                contents: Data(Self.probeSource.utf8),
                origin: .bundledStdlib
            )
            try runSema(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "bundled probe compilation should not emit errors: \(ctx.diagnostics.diagnostics)"
            )
            result = (try #require(ctx.sema), ctx.interner)
        }
        return try #require(result)
    }

    private func memberSlotNames(
        _ layout: NominalLayout,
        sema: SemaModule,
        interner: StringInterner
    ) -> [(name: String, slot: Int)] {
        layout.vtableSlots
            .map { symbolID, slot in
                (sema.symbols.symbol(symbolID).map { interner.resolve($0.name) } ?? "?", slot)
            }
            .sorted { $0.slot < $1.slot }
    }

    @Test
    func testInterfaceReceiverExternalExtensionAliasExcludedFromLayout() throws {
        let (sema, interner) = try compileWithBundledProbe()
        let charSequenceFQ = ["kotlin", "CharSequence"].map { interner.intern($0) }
        let charSequenceSymbol = try #require(sema.symbols.lookup(fqName: charSequenceFQ))
        let layout = try #require(sema.symbols.nominalLayout(for: charSequenceSymbol))

        // The alias exists under the receiver FQ name for owner+member lookup.
        let aliasFQ = charSequenceFQ + [interner.intern("__kk_kuu545_iface_probe")]
        let aliasSymbol = try #require(sema.symbols.lookupAll(fqName: aliasFQ).first)
        let aliasInfo = try #require(sema.symbols.symbol(aliasSymbol))
        #expect(aliasInfo.flags.contains(.extensionMemberAlias))
        #expect(sema.symbols.externalLinkName(for: aliasSymbol) == "__kk_kuu545_iface_probe")

        // But it owns no vtable slot: CharSequence's method space is exactly
        // get@0/subSequence@1, and the `length` property getter stays at
        // itable slot 2 — the contract runtimeRegisterCharSequenceItable
        // hardcodes for String objects.
        #expect(layout.vtableSize == 2)
        #expect(layout.vtableSlots[aliasSymbol] == nil)
        let slots = memberSlotNames(layout, sema: sema, interner: interner)
        #expect(slots.map(\.name) == ["get", "subSequence"])
        #expect(slots.map(\.slot) == [0, 1])

        let lengthSymbol = try #require(sema.symbols.lookup(
            fqName: charSequenceFQ + [interner.intern("length")]
        ))
        #expect(
            kirInterfacePropertyGetterSlot(
                interfaceProperty: lengthSymbol,
                interfaceSymbol: charSequenceSymbol,
                sema: sema,
                interner: interner
            ) == 2
        )
    }

    /// The same alias on a nominal *class* receiver must likewise stay out of
    /// the class's own-method slot space — extension aliases are statically
    /// dispatched and never need a vtable entry.
    @Test
    func testClassReceiverExternalExtensionAliasExcludedFromLayout() throws {
        let (sema, interner) = try compileWithBundledProbe()
        let stringBuilderFQ = ["kotlin", "text", "StringBuilder"].map { interner.intern($0) }
        let stringBuilderSymbol = try #require(sema.symbols.lookup(fqName: stringBuilderFQ))
        let layout = try #require(sema.symbols.nominalLayout(for: stringBuilderSymbol))

        let aliasFQ = stringBuilderFQ + [interner.intern("__kk_kuu545_string_probe")]
        let aliasSymbol = try #require(sema.symbols.lookupAll(fqName: aliasFQ).first)
        #expect(sema.symbols.symbol(aliasSymbol)?.flags.contains(.extensionMemberAlias) == true)
        #expect(layout.vtableSlots[aliasSymbol] == nil)
    }
}
