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
        let sema = SemaModule(
            symbols: fixture.symbols,
            types: fixture.types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
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

        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
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
        let sema = SemaModule(
            symbols: fixture.symbols,
            types: fixture.types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )
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
}
