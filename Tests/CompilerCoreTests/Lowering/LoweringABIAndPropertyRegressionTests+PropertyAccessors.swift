#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension LoweringABIAndPropertyRegressionTests {
    // MARK: - Property Lowering Tests

    @Test
    func testPropertyLoweringRewritesGetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let callerSym = SymbolID(rawValue: 51)
        let propertyName = interner.intern("value")
        let propertySym = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: [propertyName],
            declSite: nil,
            visibility: .public
        )

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        _ = try runLowering(module: module, interner: interner, moduleName: "PropGetter", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            Issue.record("expected function")
            return
        }

        let expectedGetterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        #expect(callSymbols.contains(expectedGetterSymbol),
                      "Expected synthetic getter symbol \(expectedGetterSymbol), got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(!callees.contains("kk_property_access"))
    }

    @Test
    func testPropertyLoweringRewritesSetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let callerSym = SymbolID(rawValue: 61)
        let propertyName = interner.intern("value")
        let propertySym = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: [propertyName],
            declSite: nil,
            visibility: .public
        )

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let value = arena.appendExpr(.temporary(1), type: types.anyType)
        let result = arena.appendExpr(.temporary(2), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("setter_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("set"),
                    arguments: [receiver, value],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        _ = try runLowering(module: module, interner: interner, moduleName: "PropSetter", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            Issue.record("expected function")
            return
        }

        let expectedSetterSymbol = SymbolID(rawValue: -13000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        #expect(callSymbols.contains(expectedSetterSymbol),
                      "Expected synthetic setter symbol \(expectedSetterSymbol), got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(!callees.contains("kk_property_access"))
    }

    @Test
    func testPropertyLoweringPreservesGetSetCallsWithoutSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 70)
        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("no_sym_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        _ = try runLowering(module: module, interner: interner, moduleName: "PropNoSym")

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            Issue.record("expected function")
            return
        }

        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("get"))
        #expect(!callees.contains("kk_property_access"))
    }

    @Test
    func testPropertyLoweringRewritesBackingFieldCopyToDirectSetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let classSym = symbols.define(
            kind: .class,
            name: interner.intern("Foo"),
            fqName: [interner.intern("Foo")],
            declSite: nil,
            visibility: .public
        )
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("myProp"),
            fqName: [interner.intern("Foo"), interner.intern("myProp")],
            declSite: nil,
            visibility: .public,
            flags: [.mutable]
        )
        symbols.setParentSymbol(classSym, for: propertySym)
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_myProp"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_myProp")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        // PropertyLoweringPass must not rewrite a backing-field copy into a
        // call targeting a setter symbol unless a real setter accessor
        // function was actually emitted for it — otherwise codegen is left
        // with a call to a function that doesn't exist. So the rewrite target
        // needs a genuine (receiver, value) -> Unit setter accessor present
        // in the module, matching the shape lowerAccessorBody synthesizes.
        let expectedSetterSymbol = SymbolID(rawValue: -13000 - propertySym.rawValue)
        let setterReceiverSym = SymbolID(rawValue: 90)
        let setterValueSym = SymbolID(rawValue: 91)
        let setterFn = KIRFunction(
            symbol: expectedSetterSymbol,
            name: interner.intern("set"),
            params: [
                KIRParameter(symbol: setterReceiverSym, type: types.anyType),
                KIRParameter(symbol: setterValueSym, type: types.anyType),
            ],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        _ = arena.appendDecl(.function(setterFn))

        // The caller simulates constructor-side field-initializer wiring: a
        // function with its own receiver parameter (the instance under
        // construction) that writes directly to the backing field. The
        // rewrite must forward this receiver alongside the value — a setter
        // accessor takes (receiver, value), not just the value.
        let callerReceiverSym = SymbolID(rawValue: 101)
        let callerSym = SymbolID(rawValue: 100)
        let fromExpr = arena.appendExpr(.intLiteral(42), type: types.anyType)
        let toExpr = arena.appendExpr(.symbolRef(backingFieldSym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("bf_setter"),
            params: [KIRParameter(symbol: callerReceiverSym, type: types.anyType)],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        _ = try runLowering(module: module, interner: interner, moduleName: "BFSetter", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            Issue.record("expected function")
            return
        }

        let setterCalls = lowered.body.compactMap { instruction -> [KIRExprID]? in
            guard case let .call(sym, _, arguments, _, _, _, _, _) = instruction, sym == expectedSetterSymbol else {
                return nil
            }
            return arguments
        }
        #expect(setterCalls.count == 1,
                      "Expected exactly one setter call for \(expectedSetterSymbol), got body: \(lowered.body)")
        #expect(setterCalls.first?.count == 2,
                      "Setter accessor takes (receiver, value); expected 2 arguments, got: \(String(describing: setterCalls.first))")

        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(callees.contains("set"))
        #expect(!callees.contains("kk_property_access"))

        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        #expect(!hasCopy, "Backing field copy should have been rewritten to a setter call")
    }

    @Test
    func testPropertyLoweringKeepsDirectCopyWhenNoSetterAccessorEmitted() throws {
        // A `var` whose only customized accessor is the getter (no explicit
        // `set(value) { ... }` block) never gets a setter accessor function
        // synthesized (see KIRLoweringDriver+ModuleLowering+PropertyDecl.swift).
        // Rewriting a backing-field copy into a call to that non-existent
        // setter symbol would leave codegen with an unresolvable callee, so
        // the rewrite must keep the direct copy instead — regardless of the
        // property's mutability.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let classSym = symbols.define(
            kind: .class,
            name: interner.intern("Foo"),
            fqName: [interner.intern("Foo")],
            declSite: nil,
            visibility: .public
        )
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("cache"),
            fqName: [interner.intern("Foo"), interner.intern("cache")],
            declSite: nil,
            visibility: .public,
            flags: [.mutable]
        )
        symbols.setParentSymbol(classSym, for: propertySym)
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_cache"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_cache")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        // No setter accessor function is registered anywhere in this module —
        // only the getter (`function.symbol` below), matching a getter-only
        // customized property. `field = ...` inside that getter must remain a
        // direct write; it must never be routed through a setter accessor.
        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySym)
        let receiverSym = SymbolID(rawValue: 90)
        let fromExpr = arena.appendExpr(.intLiteral(42), type: types.anyType)
        let toExpr = arena.appendExpr(.symbolRef(backingFieldSym), type: types.anyType)

        let getterFn = KIRFunction(
            symbol: getterSymbol,
            name: interner.intern("get"),
            params: [KIRParameter(symbol: receiverSym, type: types.anyType)],
            returnType: types.anyType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(getterFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        _ = try runLowering(module: module, interner: interner, moduleName: "NoSetterAccessor", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            Issue.record("expected function")
            return
        }

        // No function in this module has `expectedSetterSymbol` (or any
        // symbol at all — the only calls that legitimately appear here are
        // ABILoweringPass's later, unrelated `Any`-boxing conversions, which
        // always carry `symbol: nil`). If PropertyLoweringPass had
        // (incorrectly) rewritten the copy into a setter call, `symbol`
        // would be non-nil and `callee` would resolve to "set".
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        #expect(callSymbols.isEmpty,
                      "No setter accessor exists for this property; expected no symbol-bound calls, got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(!callees.contains("set"),
                      "Backing field write should not be routed through a setter accessor that was never emitted")
    }

    @Test
    func testPropertyLoweringKeepsDirectCopyForFieldWriteInsideOwnGetter() throws {
        // Kotlin's `field` keyword always writes directly to backing storage,
        // even from within the property's own getter (e.g. a lazy-caching
        // getter that does `field = compute()`) — it must never invoke the
        // setter, even when the property DOES have a real custom setter.
        // Rewriting it into a setter call would apply the setter's own
        // transformation logic a second time on every read.
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let classSym = symbols.define(
            kind: .class,
            name: interner.intern("Foo"),
            fqName: [interner.intern("Foo")],
            declSite: nil,
            visibility: .public
        )
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("v"),
            fqName: [interner.intern("Foo"), interner.intern("v")],
            declSite: nil,
            visibility: .public,
            flags: [.mutable]
        )
        symbols.setParentSymbol(classSym, for: propertySym)
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_v"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_v")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        // A real setter accessor DOES exist for this property (unlike the
        // no-setter-accessor test above) — the getter-exclusion must still
        // keep the write direct even so.
        let setterSymbol = SyntheticSymbolScheme.propertySetterAccessorSymbol(for: propertySym)
        let setterFn = KIRFunction(
            symbol: setterSymbol,
            name: interner.intern("set"),
            params: [
                KIRParameter(symbol: SymbolID(rawValue: 90), type: types.anyType),
                KIRParameter(symbol: SymbolID(rawValue: 91), type: types.anyType),
            ],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        _ = arena.appendDecl(.function(setterFn))

        let getterSymbol = SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: propertySym)
        let receiverSym = SymbolID(rawValue: 92)
        let fromExpr = arena.appendExpr(.intLiteral(42), type: types.anyType)
        let toExpr = arena.appendExpr(.symbolRef(backingFieldSym), type: types.anyType)

        let getterFn = KIRFunction(
            symbol: getterSymbol,
            name: interner.intern("get"),
            params: [KIRParameter(symbol: receiverSym, type: types.anyType)],
            returnType: types.anyType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(getterFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        _ = try runLowering(module: module, interner: interner, moduleName: "GetterFieldWrite", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            Issue.record("expected function")
            return
        }

        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        #expect(!callSymbols.contains(setterSymbol),
                      "field = ... inside the getter must not call the setter, got calls: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        #expect(!callees.contains("set"),
                      "field = ... inside the getter must not be routed through the setter accessor")
    }

    @Test
    func testPropertyLoweringRewritesComputedPropertySymbolRefToGetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("computed"),
            fqName: [interner.intern("Foo"), interner.intern("computed")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        // Emit a getter accessor function so PropertyLoweringPass recognises
        // this property as a computed property (it checks that the getter
        // function actually exists in the KIR module).
        let getterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let getterRetExpr = arena.appendExpr(.stringLiteral(interner.intern("hello")), type: types.anyType)
        let getterFn = KIRFunction(
            symbol: getterSymbol,
            name: interner.intern("get"),
            params: [],
            returnType: types.anyType,
            body: [
                .constValue(result: getterRetExpr, value: .stringLiteral(interner.intern("hello"))),
                .returnValue(getterRetExpr),
            ],
            isSuspend: false,
            isInline: false
        )
        _ = arena.appendDecl(.function(getterFn))

        let callerSym = SymbolID(rawValue: 200)
        let propRef = arena.appendExpr(.symbolRef(propertySym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: propRef, value: .symbolRef(propertySym)),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        _ = try runLowering(module: module, interner: interner, moduleName: "ComputedProp", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            Issue.record("expected function")
            return
        }

        let expectedGetterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        #expect(callSymbols.contains(expectedGetterSymbol),
                      "Expected getter call for computed property, got: \(callSymbols)")

        let hasSymbolRef = lowered.body.contains { instruction in
            if case let .constValue(_, value) = instruction,
               case let .symbolRef(sym) = value,
               sym == propertySym
            {
                return true
            }
            return false
        }
        #expect(!hasSymbolRef,
                       "constValue(.symbolRef) for computed property should have been rewritten to a getter call")
    }

    @Test
    func testPropertyLoweringPreservesBackedPropertySymbolRef() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("backed"),
            fqName: [interner.intern("Foo"), interner.intern("backed")],
            declSite: nil,
            visibility: .public,
            flags: [.mutable]
        )
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_backed"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_backed")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        let callerSym = SymbolID(rawValue: 300)
        let propRef = arena.appendExpr(.symbolRef(propertySym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: propRef, value: .symbolRef(propertySym)),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let funcID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [funcID])], arena: arena)

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
        _ = try runLowering(module: module, interner: interner, moduleName: "BackedProp", sema: sema)

        guard case let .function(lowered)? = module.arena.decl(funcID) else {
            Issue.record("expected function")
            return
        }

        let hasSymbolRef = lowered.body.contains { instruction in
            if case let .constValue(_, value) = instruction,
               case let .symbolRef(sym) = value,
               sym == propertySym
            {
                return true
            }
            return false
        }
        #expect(hasSymbolRef,
                      "constValue(.symbolRef) for backed property should NOT be rewritten")
    }

    @Test
    func testGetterOnlyComputedPropertyEmitsNoGlobal() throws {
        let source = """
        package test

        class Widget {
            val computed: String get() = "hello"

            var backed: Int = 0
                get() = field
                set(value) { field = value }
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            Issue.record("KIR module not available")
            return
        }

        let interner = ctx.interner

        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        let computedName = interner.intern("computed")
        let computedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == computedName
        }
        #expect(computedSymbols.isEmpty,
                      "Getter-only computed property should NOT have a KIRGlobal, found: \(computedSymbols)")

        let backedName = interner.intern("backed")
        let backedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == backedName
        }
        #expect(!backedSymbols.isEmpty,
                       "Var property with backing field should have a KIRGlobal")

        let sema = try #require(ctx.sema, "Sema module not available")
        let computedPropertySymbol = try #require(
            sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .property && symbol.name == computedName
            }),
            "computed property symbol not found in sema"
        )

        let expectedGetterSymbol = SymbolID(rawValue: -12000 - computedPropertySymbol.id.rawValue)
        let getterSymbols = findAllKIRFunctions(in: module).compactMap { kirFunc -> SymbolID? in
            guard interner.resolve(kirFunc.name) == "get" else { return nil }
            return kirFunc.symbol
        }
        #expect(getterSymbols.contains(expectedGetterSymbol),
                      "Getter accessor symbol for computed property should be emitted. expected=\(expectedGetterSymbol), actual=\(getterSymbols)")
    }

    @Test
    func testGetterOnlyComputedPropertyOverrideEmitsAccessors() throws {
        let source = """
        package test

        open class Base {
            open val label: String get() = "base"
        }

        class Derived : Base() {
            override val label: String get() = "derived"
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            Issue.record("KIR module not available")
            return
        }

        let interner = ctx.interner

        let getName = interner.intern("get")
        let getterFunctions = findAllKIRFunctions(in: module).filter { kirFunc in
            kirFunc.name == getName
        }

        #expect(
            getterFunctions.count >= 2,
            "Both base and override should emit getter accessors, found: \(getterFunctions.count)"
        )

        let labelName = interner.intern("label")
        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }
        let labelGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == labelName
        }
        #expect(labelGlobals.isEmpty,
                      "Getter-only computed property override should NOT have a KIRGlobal, found: \(labelGlobals)")
    }

    @Test
    func testCustomGetterSetterPropertyEmitsAccessorsAndBackingField() throws {
        let source = """
        package test

        class Counter {
            var count: Int = 0
                get() = field
                set(value) { field = value }

            val label: String get() = "Count"
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            Issue.record("KIR module not available")
            return
        }

        let interner = ctx.interner

        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        let countName = interner.intern("count")
        let countGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == countName
        }
        #expect(!countGlobals.isEmpty,
                       "Var property with custom getter/setter should have a KIRGlobal")

        let labelName = interner.intern("label")
        let labelGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == labelName
        }
        #expect(labelGlobals.isEmpty,
                      "Getter-only computed property should NOT have a KIRGlobal, found: \(labelGlobals)")

        let getName = interner.intern("get")
        let getterFunctions = findAllKIRFunctions(in: module).filter { kirFunc in
            kirFunc.name == getName
        }
        #expect(
            getterFunctions.count >= 1,
            "Should have at least 1 getter accessor (for label)"
        )
    }

    @Test
    func testTopLevelGetterOnlyComputedPropertyEmitsNoGlobal() throws {
        let source = """
        package test

        var stored: Int = 42
        val computed: Int get() = stored

        fun readComputed(): Int {
            return computed
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            Issue.record("KIR module not available")
            return
        }

        let interner = ctx.interner

        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case let .global(global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        // Top-level "computed" should NOT have a KIRGlobal.
        let computedName = interner.intern("computed")
        let computedGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == computedName
        }
        #expect(
            computedGlobals.isEmpty,
            "Top-level getter-only computed property should NOT have a KIRGlobal"
        )

        // Top-level "stored" SHOULD have a KIRGlobal.
        let storedName = interner.intern("stored")
        let storedGlobals = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == storedName
        }
        #expect(!storedGlobals.isEmpty,
                       "Top-level stored property should have a KIRGlobal")

        // Verify that readComputed() was lowered so that the read of
        // "computed" became a getter accessor call (not loadGlobal).
        let sema = try #require(ctx.sema)
        let computedPropSym = try #require(
            sema.symbols.allSymbols().first(where: {
                $0.kind == .property && $0.name == computedName
            }),
            "computed property symbol not found"
        )
        let getterSym = SyntheticSymbolScheme
            .propertyGetterAccessorSymbol(for: computedPropSym.id)

        // Find readComputed and check its body for a getter call.
        let readName = interner.intern("readComputed")
        let readerFn = findAllKIRFunctions(in: module).first { kirFunc in
            kirFunc.name == readName
        }
        let reader = try #require(readerFn, "readComputed not found")

        let hasGetterCall = reader.body.contains { inst in
            if case let .call(symbol, _, _, _, _, _, _, _) = inst {
                return symbol == getterSym
            }
            return false
        }
        #expect(
            hasGetterCall,
            "Read of top-level computed property should lower to getter call"
        )

        // Verify no loadGlobal remains for the computed symbol.
        let hasLoadGlobal = reader.body.contains { inst in
            if case let .loadGlobal(_, sym) = inst {
                return sym == computedPropSym.id
            }
            return false
        }
        #expect(
            !hasLoadGlobal,
            "loadGlobal for computed property should be rewritten"
        )
    }
}
#endif
