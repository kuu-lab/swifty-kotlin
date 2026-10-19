@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeMutableListMixedElementTests {
    @Test(arguments: ["set", "iterator-set"], ["Int", "Char", "null"])
    func replacingFirstRetainsInsertedTypeAfterCharElements(operation: String, elementType: String) throws {
        let listRaw = kk_array_list_of(0, 0)
        var thrown = 0
        _ = kk_mutable_list_add(listRaw, kk_box_char(55), &thrown)
        #expect(thrown == 0)
        let element: Int = switch elementType {
        case "Int": kk_box_int(6)
        case "Char": kk_box_char(54)
        default: runtimeNullSentinelInt
        }
        switch operation {
        case "set":
            _ = kk_mutable_list_set(listRaw, 0, element, &thrown)
        default:
            let iterator = kk_list_iterator(listRaw)
            _ = kk_list_iterator_next(iterator, &thrown)
            _ = runtimeListIteratorSet(iterator, element, &thrown)
        }
        #expect(thrown == 0)
        let list = try #require(runtimeListBox(from: listRaw))
        #expect(list.count == 1)
        assertInsertedElement(list.values[0], matches: elementType)
    }

    @Test(arguments: ["add", "collection-add", "add-at", "iterator-add"], ["Int", "Char", "null"])
    func appendingOrInsertingRetainsInsertedTypeAfterCharElements(operation: String, elementType: String) throws {
        let listRaw = kk_array_list_of(0, 0)
        var thrown = 0
        _ = kk_mutable_list_add(listRaw, kk_box_char(55), &thrown)
        #expect(thrown == 0)
        let element: Int = switch elementType {
        case "Int": kk_box_int(6)
        case "Char": kk_box_char(54)
        default: runtimeNullSentinelInt
        }
        switch operation {
        case "add":
            _ = kk_mutable_list_add(listRaw, element, &thrown)
        case "collection-add":
            _ = kk_mutable_collection_add_throwing(listRaw, element, &thrown)
        case "add-at":
            _ = kk_mutable_list_add_at(listRaw, 1, element, &thrown)
        default:
            let iterator = kk_list_iterator(listRaw)
            _ = kk_list_iterator_next(iterator, &thrown)
            _ = runtimeListIteratorAdd(iterator, element, &thrown)
        }
        #expect(thrown == 0)
        let list = try #require(runtimeListBox(from: listRaw))
        #expect(list.count == 2)
        #expect(list.values[0].tag == RuntimeValue.charTag)
        #expect(list.values[0].payload0 == 55)
        assertInsertedElement(list.values[1], matches: elementType)
    }

    private func assertInsertedElement(_ inserted: RuntimeValue, matches elementType: String) {
        switch elementType {
        case "Int":
            #expect(inserted.tag != RuntimeValue.charTag)
            #expect(kk_unbox_int(inserted.legacyRawValue) == 6)
        case "Char":
            #expect(inserted.tag == RuntimeValue.charTag)
            #expect(inserted.payload0 == 54)
        default:
            #expect(inserted.legacyRawValue == runtimeNullSentinelInt)
            #expect(inserted.tag != RuntimeValue.charTag)
        }
    }
}
