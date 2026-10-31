#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

// KUU-3807: an interface property default getter inherited by an enum entry
// is read through an itable-dispatched `.virtualCall`. The dispatch resolves
// the callee from the receiver object's registered itable, so the receiver
// must arrive boxed — a statically enum-typed receiver is a raw ordinal at
// KIR level and `kk_itable_lookup(_dynamic)` cannot dispatch on it
// (`KSWIFTK-RUNTIME-0001` before the fix). Boxing also carries the entry's
// `kk_object_register_itable_*` registrations the lookup needs.
extension LoweringPassRegressionTests {
    @Test
    func testInterfaceDefaultGetterVirtualCallBoxesEnumReceiver() throws {
        let source = """
        interface I { val stuff: String get() = "OK" }
        enum class E : I {
            X;
            fun test() = stuff
        }
        fun main() { println(E.X.test()) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumInterfaceDefaultGetter",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(
                !ctx.diagnostics.hasError,
                "interface default getter on enum entry should lower: \(ctx.diagnostics.diagnostics.map(\.message))"
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "test", in: module, interner: ctx.interner)

            // The canonical enum box registers the interface + its member
            // slots on the tagged entry value at this boundary.
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains(RuntimeCall.enumBoxOrdinal.name))
            #expect(callees.contains(RuntimeCall.objectRegisterItableInterface.name))

            // Every itable-dispatched virtual call must see the boxed
            // receiver, never the raw ordinal `this`.
            var boxedResults: Set<KIRExprID> = []
            for instruction in body {
                guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == RuntimeCall.enumBoxOrdinal.name,
                      let result
                else {
                    continue
                }
                boxedResults.insert(result)
            }
            let itableReceivers = body.compactMap { instruction -> KIRExprID? in
                guard case let .virtualCall(_, _, receiver, _, _, _, _, dispatch) = instruction,
                      case .itableDynamic = dispatch
                else {
                    return nil
                }
                return receiver
            }
            #expect(!itableReceivers.isEmpty, "expected an itable getter read in test()")
            #expect(
                itableReceivers.allSatisfy { boxedResults.contains($0) },
                "itable-dispatched receiver must be the enum box, not the raw ordinal"
            )
        }
    }

    @Test
    func testInterfaceGetterReadOnValuesElementBoxesReceiver() throws {
        let source = """
        interface I { val stuff: String get() = "OK" }
        enum class E : I { X }
        fun main() {
            println(E.X.stuff)
            println(E.values()[0].stuff)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumInterfaceGetterElementRead",
                emit: .kirDump
            )
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError)

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            var boxedResults: Set<KIRExprID> = []
            for instruction in body {
                guard case let .call(_, callee, _, result, _, _, _, _) = instruction,
                      ctx.interner.resolve(callee) == RuntimeCall.enumBoxOrdinal.name,
                      let result
                else {
                    continue
                }
                boxedResults.insert(result)
            }
            let itableReceivers = body.compactMap { instruction -> KIRExprID? in
                guard case let .virtualCall(_, _, receiver, _, _, _, _, dispatch) = instruction,
                      case .itableDynamic = dispatch
                else {
                    return nil
                }
                return receiver
            }
            #expect(itableReceivers.count == 2)
            #expect(itableReceivers.allSatisfy { boxedResults.contains($0) })
        }
    }

    /// The compiler-provided `E.entries` EnumEntries stub is a `.static`
    /// member — it can never implement an interface's instance `entries`
    /// property. `kirFindOverridePropertyGetter` must skip it and resolve the
    /// interface's own accessor; registering the stub's bodiless accessor
    /// left a dangling `__itable_impl_<id>` reference (KSWIFTK-LINK-0001).
    @Test
    func testStaticEnumEntriesStubNotReturnedAsInterfaceGetterImpl() throws {
        let source = """
        interface I { val entries: String get() = "OK" }
        enum class E : I { X }
        fun main() { val i: I = E.X; println(i.entries) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "EnumEntriesStubVsInterfaceProperty",
                emit: .kirDump
            )
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError)
            let sema = try #require(ctx.sema)

            let iSym = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("I")]))
            let eSym = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("E")]))
            #expect(sema.symbols.symbol(iSym)?.kind == .interface)
            let iEntries = try #require(
                sema.symbols.lookup(fqName: [ctx.interner.intern("I"), ctx.interner.intern("entries")])
            )
            let implGetter = try #require(
                kirFindOverridePropertyGetter(for: iEntries, in: eSym, sema: sema),
                "the interface default getter must fill the itable slot"
            )
            let decoded = try #require(SyntheticSymbolScheme.decodedPropertyAccessor(implGetter))
            #expect(
                decoded.property == iEntries,
                "the `.static` E.entries stub must not be picked as the interface getter implementation"
            )

            // The setter counterpart shares the lookup rule.
            let implSetter = kirFindOverridePropertySetter(for: iEntries, in: eSym, sema: sema)
            if let implSetter,
               let setterDecoded = SyntheticSymbolScheme.decodedPropertyAccessor(implSetter)
            {
                #expect(setterDecoded.property == iEntries)
            }
        }
    }
}
#endif
