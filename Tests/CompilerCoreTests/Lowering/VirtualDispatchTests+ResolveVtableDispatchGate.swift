#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

// DEBT-KIR-001: vtable dispatch is enabled for compiler-created objects via
// allocation-time vtable method registration, with kk_alloc/KTypeInfo remaining
// as the runtime fallback path.

extension VirtualDispatchTests {
    @Test func testHiddenFinalMemberCallsStayDirectInClassHierarchy() throws {
        let source = """
        open class Parser {
            private fun inspect(): Int = 7
            internal fun inspectInternal(): Int = 9
            fun implicit(): Int = inspect()
            fun explicit(): Int = this.inspect()
            fun safe(): Int? = this?.inspect()
            fun reference(): () -> Int = this::inspect
            fun internalHelper(): Int = inspectInternal()
            open fun visible(): Int = 1
            fun control(): Int = visible()
            internal open fun internalVisible(): Int = 3
            fun internalControl(): Int = internalVisible()
        }
        class Child : Parser() {
            override fun visible(): Int = 2
            override fun internalVisible(): Int = 4
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "PrivateDispatch", includeStdlib: false)
            try runToKIR(ctx)
            try #require(!ctx.diagnostics.hasError)
            let module = try #require(ctx.kir)
            for function in findAllKIRFunctions(in: module) {
                for instruction in function.body {
                    if case let .virtualCall(symbol?, _, _, _, _, _, _, _) = instruction {
                        let name = ctx.sema?.symbols.symbol(symbol)?.name
                        #expect(name != ctx.interner.intern("inspect"))
                        #expect(name != ctx.interner.intern("inspectInternal"))
                    }
                }
            }
            for caller in ["implicit", "explicit", "safe", "internalHelper"] {
                let body = try findKIRFunctionBody(named: caller, in: module, interner: ctx.interner)
                #expect(body.contains {
                    if case let .call(symbol?, _, _, _, _, _, _, _) = $0 {
                        let name = ctx.sema?.symbols.symbol(symbol)?.name
                        return name == ctx.interner.intern("inspect") || name == ctx.interner.intern("inspectInternal")
                    }
                    return false
                }, "\(caller) must retain the direct helper call")
            }
            for caller in ["control", "internalControl"] {
                let body = try findKIRFunctionBody(named: caller, in: module, interner: ctx.interner)
                #expect(body.contains {
                    if case .virtualCall = $0 { return true }
                    return false
                }, "Overridable members must retain virtual dispatch")
            }
        }
    }

    /// Isolated unit test for `resolveVirtualDispatch` on an open-class hierarchy.
    /// Open-class hierarchies must select vtable dispatch when the callee has a
    /// layout slot and the parent has known subtypes.
    @Test func testResolveVtableDispatchReturnsVtableForOpenClassWithSubtypes() {
        let fixture = makeVtableFixture()
        let sema = makeSemaModule(symbols: fixture.symbols, types: fixture.types).ctx
        let loweringContext = KIRLoweringContext()
        loweringContext.initializeSyntheticLambdaSymbolAllocator(sema: sema)
        let driver = KIRLoweringDriver(ctx: loweringContext)
        let callLowerer = CallLowerer(driver: driver)

        let animalType = fixture.types.make(.classType(ClassType(
            classSymbol: fixture.classSym,
            args: [],
            nullability: .nonNull
        )))

        let dispatch = callLowerer.resolveVirtualDispatch(
            callee: fixture.methodSym,
            receiverTypeID: animalType,
            sema: sema,
            interner: fixture.interner
        )

        #expect(dispatch == .vtable(slot: 0))
    }

    /// Confirms that a class without known subtypes also skips vtable dispatch.
    @Test func testResolveVtableDispatchReturnsNilForClassWithoutSubtypes() {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let classSym = symbols.define(
            kind: .class,
            name: interner.intern("FinalAnimal"),
            fqName: [interner.intern("FinalAnimal")],
            declSite: nil,
            visibility: .public
        )
        let methodSym = symbols.define(
            kind: .function,
            name: interner.intern("speak"),
            fqName: [interner.intern("FinalAnimal"), interner.intern("speak")],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(classSym, for: methodSym)
        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: 0,
                instanceSizeWords: 2,
                vtableSlots: [methodSym: 0],
                itableSlots: [:],
                superClass: nil
            ),
            for: classSym
        )

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        let loweringContext = KIRLoweringContext()
        loweringContext.initializeSyntheticLambdaSymbolAllocator(sema: sema)
        let driver = KIRLoweringDriver(ctx: loweringContext)
        let callLowerer = CallLowerer(driver: driver)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [],
            nullability: .nonNull
        )))

        let dispatch = callLowerer.resolveVirtualDispatch(
            callee: methodSym,
            receiverTypeID: receiverType,
            sema: sema,
            interner: interner
        )

        #expect(dispatch == nil, "Class without subtypes should use static dispatch")
    }

    @Test func testResolveVtableDispatchExpectedSlotWhenEnabled() throws {
        let fixture = makeVtableFixture()
        let sema = makeSemaModule(symbols: fixture.symbols, types: fixture.types).ctx
        let loweringContext = KIRLoweringContext()
        loweringContext.initializeSyntheticLambdaSymbolAllocator(sema: sema)
        let driver = KIRLoweringDriver(ctx: loweringContext)
        let callLowerer = CallLowerer(driver: driver)

        let animalType = fixture.types.make(.classType(ClassType(
            classSymbol: fixture.classSym,
            args: [],
            nullability: .nonNull
        )))

        let dispatch = callLowerer.resolveVirtualDispatch(
            callee: fixture.methodSym,
            receiverTypeID: animalType,
            sema: sema,
            interner: fixture.interner
        )

        guard case let .vtable(slot) = dispatch else {
            Issue.record("Expected vtable dispatch for open class with subtypes, got \(String(describing: dispatch))")
            return
        }
        #expect(slot == 0, "speak should occupy vtable slot 0 in makeVtableFixture")
    }

    /// Verifies vtable slot selection is per-callee, not always slot 0.
    /// A class with two virtual methods must dispatch each to its own slot.
    @Test func testResolveVtableDispatchSelectsCorrectNonZeroSlot() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let classSym = symbols.define(
            kind: .class,
            name: interner.intern("Shape"),
            fqName: [interner.intern("Shape")],
            declSite: nil,
            visibility: .public
        )
        let subclassSym = symbols.define(
            kind: .class,
            name: interner.intern("Circle"),
            fqName: [interner.intern("Circle")],
            declSite: nil,
            visibility: .public
        )
        symbols.setDirectSupertypes([classSym], for: subclassSym)

        let drawSym = symbols.define(
            kind: .function,
            name: interner.intern("draw"),
            fqName: [interner.intern("Shape"), interner.intern("draw")],
            declSite: nil,
            visibility: .public
        )
        let areaSym = symbols.define(
            kind: .function,
            name: interner.intern("area"),
            fqName: [interner.intern("Shape"), interner.intern("area")],
            declSite: nil,
            visibility: .public
        )
        symbols.setParentSymbol(classSym, for: drawSym)
        symbols.setParentSymbol(classSym, for: areaSym)

        symbols.setNominalLayout(
            NominalLayout(
                objectHeaderWords: 2,
                instanceFieldCount: 0,
                instanceSizeWords: 2,
                vtableSlots: [drawSym: 0, areaSym: 1],
                itableSlots: [:],
                superClass: nil
            ),
            for: classSym
        )

        let sema = makeSemaModule(symbols: symbols, types: types).ctx
        let loweringContext = KIRLoweringContext()
        loweringContext.initializeSyntheticLambdaSymbolAllocator(sema: sema)
        let driver = KIRLoweringDriver(ctx: loweringContext)
        let callLowerer = CallLowerer(driver: driver)

        let shapeType = types.make(.classType(ClassType(
            classSymbol: classSym,
            args: [],
            nullability: .nonNull
        )))

        let drawDispatch = callLowerer.resolveVirtualDispatch(
            callee: drawSym,
            receiverTypeID: shapeType,
            sema: sema,
            interner: interner
        )
        let areaDispatch = callLowerer.resolveVirtualDispatch(
            callee: areaSym,
            receiverTypeID: shapeType,
            sema: sema,
            interner: interner
        )

        guard case let .vtable(drawSlot) = drawDispatch else {
            Issue.record("Expected vtable dispatch for draw, got \(String(describing: drawDispatch))")
            return
        }
        guard case let .vtable(areaSlot) = areaDispatch else {
            Issue.record("Expected vtable dispatch for area, got \(String(describing: areaDispatch))")
            return
        }
        #expect(drawSlot == 0, "draw should occupy vtable slot 0")
        #expect(areaSlot == 1, "area should occupy vtable slot 1")
    }
}
#endif
