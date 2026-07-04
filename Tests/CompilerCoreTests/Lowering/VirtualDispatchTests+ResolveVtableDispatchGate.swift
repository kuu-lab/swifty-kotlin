@testable import CompilerCore
import Foundation
import XCTest

// DEBT-KIR-001 / GEN-VTABLE-DISABLE: vtable dispatch resolution is gated until
// codegen emits KTypeInfo vtables and class construction uses kk_alloc.

extension VirtualDispatchTests {
    /// Isolated unit test for `resolveVirtualDispatch` on an open-class hierarchy.
    /// While GEN-VTABLE-DISABLE is active the resolver must return `nil` so that
    /// lowering falls back to static `.call` dispatch.
    func testResolveVtableDispatchReturnsNilWhileGENVTABLEDisabled() {
        let fixture = makeVtableFixture()
        let sema = makeSemaModule(symbols: fixture.symbols, types: fixture.types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
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
            sema: sema
        )

        XCTAssertNil(
            dispatch,
            "GEN-VTABLE-DISABLE: open class with subtypes must not select vtable dispatch yet"
        )
    }

    /// Confirms that a class without known subtypes also skips vtable dispatch.
    func testResolveVtableDispatchReturnsNilForClassWithoutSubtypes() {
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

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
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
            sema: sema
        )

        XCTAssertNil(dispatch, "Class without subtypes should use static dispatch")
    }

    /// When DEBT-KIR-001 is resolved, flip this test to assert `.vtable(slot:)`.
    func testResolveVtableDispatchExpectedSlotWhenEnabled() throws {
        throw XCTSkip(
            "GEN-VTABLE-DISABLE (DEBT-KIR-001): re-enable after codegen emits KTypeInfo vtables and class ctor uses kk_alloc"
        )
        let fixture = makeVtableFixture()
        let sema = makeSemaModule(symbols: fixture.symbols, types: fixture.types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
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
            sema: sema
        )

        guard case let .vtable(slot) = dispatch else {
            XCTFail("Expected vtable dispatch for open class with subtypes, got \(String(describing: dispatch))")
            return
        }
        XCTAssertEqual(slot, 0, "speak should occupy vtable slot 0 in makeVtableFixture")
    }

    /// Verifies vtable slot selection is per-callee, not always slot 0.
    /// A class with two virtual methods must dispatch each to its own slot.
    /// Gated on the same prerequisites as the single-method case.
    func testResolveVtableDispatchSelectsCorrectNonZeroSlot() throws {
        throw XCTSkip(
            "GEN-VTABLE-DISABLE (DEBT-KIR-001): re-enable after codegen emits KTypeInfo vtables and class ctor uses kk_alloc"
        )
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

        let sema = makeSemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine()).ctx
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
            sema: sema
        )
        let areaDispatch = callLowerer.resolveVirtualDispatch(
            callee: areaSym,
            receiverTypeID: shapeType,
            sema: sema
        )

        guard case let .vtable(drawSlot) = drawDispatch else {
            XCTFail("Expected vtable dispatch for draw, got \(String(describing: drawDispatch))")
            return
        }
        guard case let .vtable(areaSlot) = areaDispatch else {
            XCTFail("Expected vtable dispatch for area, got \(String(describing: areaDispatch))")
            return
        }
        XCTAssertEqual(drawSlot, 0, "draw should occupy vtable slot 0")
        XCTAssertEqual(areaSlot, 1, "area should occupy vtable slot 1")
    }
}
