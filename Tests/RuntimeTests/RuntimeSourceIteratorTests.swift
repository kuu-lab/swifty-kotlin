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
    func testCharIteratorSubtypeNominalTypePreservesCharValues() {
        let charIteratorTypeID = runtimeStableNominalTypeID(fqName: "kotlin.collections.CharIterator")
        let iteratorTypeID = runtimeStableNominalTypeID(fqName: "test.CharIteratorSubclass")
        runtimeRegisterTypeEdge(childTypeID: iteratorTypeID, parentTypeID: charIteratorTypeID)

        let iterator = RuntimeObjectBox(length: 0, classID: iteratorTypeID)
        let iteratorRaw = registerRuntimeObject(iterator)
        runtimeRegisterObjectType(rawValue: iteratorRaw, classID: iteratorTypeID)

        let value = runtimeSourceIteratorValue(kk_box_char(0x0062), iteratorRaw: iteratorRaw)

        #expect(value.tag == RuntimeValue.charTag)
        #expect(value.payload0 == 0x0062)
    }

    @Test
    func testStringBackedNonCharIteratorDoesNotInferCharElementType() {
        let sourceRaw = registerRuntimeObject(RuntimeStringBox("abc"))
        let iteratorTypeID = runtimeStableNominalTypeID(fqName: "test.StringBackedIntIterator")
        let iterator = RuntimeObjectBox(length: 4, classID: iteratorTypeID)
        iterator[2] = sourceRaw
        let iteratorRaw = registerRuntimeObject(iterator)
        runtimeRegisterObjectType(rawValue: iteratorRaw, classID: iteratorTypeID)

        let value = runtimeSourceIteratorValue(kk_box_int(42), iteratorRaw: iteratorRaw)

        #expect(value.tag == RuntimeValue.rawTag)
        #expect(kk_unbox_int(value.payload0) == 42)
    }
}
#endif
