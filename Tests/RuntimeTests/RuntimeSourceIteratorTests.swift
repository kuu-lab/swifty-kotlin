#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeSourceIteratorTests {
    @Test
    func testCharSequenceIteratorNominalTypePreservesCharValues() {
        let typeID = runtimeStableNominalTypeID(fqName: "kotlin.text.CharSequenceCharIterator")
        let iterator = RuntimeObjectBox(length: 0, classID: typeID)
        let iteratorRaw = registerRuntimeObject(iterator)
        runtimeRegisterObjectType(rawValue: iteratorRaw, classID: typeID)

        let value = runtimeSourceIteratorValue(kk_box_char(0x0061), iteratorRaw: iteratorRaw)

        #expect(runtimeObjectTypeID(rawValue: iteratorRaw) == typeID)
        #expect(value.tag == RuntimeValue.charTag)
        #expect(value.payload0 == 0x0061)
    }

    @Test
    func testCharSequenceIteratorFallbackFindsSourceFieldBeyondHeaderSlots() {
        let sourceRaw = registerRuntimeObject(RuntimeStringBox("abc"))
        let iterator = RuntimeObjectBox(length: 4, classID: 0)
        iterator[2] = sourceRaw
        let iteratorRaw = registerRuntimeObject(iterator)

        let value = runtimeSourceIteratorValue(kk_box_char(0x0062), iteratorRaw: iteratorRaw)

        #expect(value.tag == RuntimeValue.charTag)
        #expect(value.payload0 == 0x0062)
    }
}
#endif
