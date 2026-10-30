#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NominalLayoutTests {
    // MARK: - Basic Init

    @Test
    func testNominalLayoutMinimalInit() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        #expect(layout.objectHeaderWords == 2)
        #expect(layout.instanceFieldCount == 0)
        #expect(layout.instanceSizeWords == 2)
        #expect(layout.fieldOffsets.isEmpty)
        #expect(layout.vtableSlots.isEmpty)
        #expect(layout.itableSlots.isEmpty)
        #expect(layout.vtableSize == 0)
        #expect(layout.itableSize == 0)
        #expect(layout.superClass == nil)
    }

    // MARK: - Field Count Inference

    @Test
    func testFieldCountInferredFromFieldOffsets() {
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 2, sym2: 3],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        #expect(layout.instanceFieldCount == 2)
    }

    @Test
    func testFieldCountUsesMaxOfDeclaredAndInferred() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 5,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 2],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        #expect(layout.instanceFieldCount == 5)
    }

    // MARK: - Instance Size Inference

    @Test
    func testInstanceSizeInferredFromFieldOffsets() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 4],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        // inferredInstanceSizeWords = max(0, max(fieldOffsets.values) + 1) = 5
        // final = max(max(0, 5), 2 + 1) = 5
        #expect(layout.instanceSizeWords == 5)
    }

    @Test
    func testInstanceSizeUsesHeaderPlusFieldCount() {
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let sym3 = SymbolID(rawValue: 2)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [sym1: 2, sym2: 3, sym3: 4],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        // inferredFieldCount = 3
        // inferredInstanceSizeWords = max(0, 4 + 1) = 5
        // final = max(max(0, 5), 2 + 3) = 5
        #expect(layout.instanceSizeWords == 5)
    }

    @Test
    func testInstanceSizeUsesMaxOfAllSources() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 10,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        #expect(layout.instanceSizeWords == 10)
    }

    @Test
    func testInstanceSizeWithEmptyFieldOffsetsUsesHeaderMinusOne() {
        let layout = NominalLayout(
            objectHeaderWords: 4,
            instanceFieldCount: 0,
            instanceSizeWords: 0,
            fieldOffsets: [:],
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        // inferredInstanceSizeWords = max(0, (nil ?? (4-1)) + 1) = 4
        // final = max(max(0, 4), 4 + 0) = 4
        #expect(layout.instanceSizeWords == 4)
    }

    // MARK: - Vtable / Itable Size Inference

    @Test
    func testVtableSizeInferredFromSlots() {
        let sym1 = SymbolID(rawValue: 0)
        let sym2 = SymbolID(rawValue: 1)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [sym1: 0, sym2: 3],
            itableSlots: [:],
            superClass: nil
        )
        // inferredVtableSize = max(vtableSlots.values) + 1 = 3 + 1 = 4
        #expect(layout.vtableSize == 4)
    }

    @Test
    func testItableSizeInferredFromSlots() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [sym1: 5],
            superClass: nil
        )
        // inferredItableSize = 5 + 1 = 6
        #expect(layout.itableSize == 6)
    }

    @Test
    func testVtableSizeUsesMaxOfDeclaredAndInferred() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [sym1: 1],
            itableSlots: [:],
            vtableSize: 10,
            superClass: nil
        )
        // inferredVtableSize = 1 + 1 = 2; declared = 10; max(10, 2) = 10
        #expect(layout.vtableSize == 10)
    }

    @Test
    func testItableSizeUsesMaxOfDeclaredAndInferred() {
        let sym1 = SymbolID(rawValue: 0)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [sym1: 1],
            itableSize: 8,
            superClass: nil
        )
        // inferredItableSize = 1 + 1 = 2; declared = 8; max(8, 2) = 8
        #expect(layout.itableSize == 8)
    }

    @Test
    func testEmptyVtableSlotsGivesZeroVtableSize() {
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        #expect(layout.vtableSize == 0)
        #expect(layout.itableSize == 0)
    }

    // MARK: - Superclass

    @Test
    func testLayoutWithSuperclass() {
        let superSym = SymbolID(rawValue: 99)
        let layout = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: superSym
        )
        #expect(layout.superClass == superSym)
    }

    // MARK: - Equatable

    @Test
    func testNominalLayoutEquality() {
        let layout1 = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        let layout2 = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        #expect(layout1 == layout2)
    }

    @Test
    func testNominalLayoutInequality() {
        let layout1 = NominalLayout(
            objectHeaderWords: 2,
            instanceFieldCount: 0,
            instanceSizeWords: 2,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        let layout2 = NominalLayout(
            objectHeaderWords: 4,
            instanceFieldCount: 0,
            instanceSizeWords: 4,
            vtableSlots: [:],
            itableSlots: [:],
            superClass: nil
        )
        #expect(layout1 != layout2)
    }

    // MARK: - NominalLayoutHint

    @Test
    func testNominalLayoutHintAllNils() {
        let hint = NominalLayoutHint(
            declaredFieldCount: nil,
            declaredInstanceSizeWords: nil,
            declaredVtableSize: nil,
            declaredItableSize: nil
        )
        #expect(hint.declaredFieldCount == nil)
        #expect(hint.declaredInstanceSizeWords == nil)
        #expect(hint.declaredVtableSize == nil)
        #expect(hint.declaredItableSize == nil)
    }

    @Test
    func testNominalLayoutHintWithValues() {
        let hint = NominalLayoutHint(
            declaredFieldCount: 3,
            declaredInstanceSizeWords: 5,
            declaredVtableSize: 2,
            declaredItableSize: 1
        )
        #expect(hint.declaredFieldCount == 3)
        #expect(hint.declaredInstanceSizeWords == 5)
        #expect(hint.declaredVtableSize == 2)
        #expect(hint.declaredItableSize == 1)
    }

    @Test
    func testNominalLayoutHintEquality() {
        let a = NominalLayoutHint(declaredFieldCount: 1, declaredInstanceSizeWords: 2, declaredVtableSize: 3, declaredItableSize: 4)
        let b = NominalLayoutHint(declaredFieldCount: 1, declaredInstanceSizeWords: 2, declaredVtableSize: 3, declaredItableSize: 4)
        #expect(a == b)
    }
}
#endif
