@testable import Runtime
import Testing

@Suite(.serialized, .runtimeIsolation(.gcOnly))
struct RuntimeMutableListMixedElementTests {
    @Test(arguments: ["add", "collection-add", "add-at", "set", "iterator-add", "iterator-set"], ["Int", "Char", "null"])
    func retainsInsertedTypeAfterCharElements(operation: String, elementType: String) throws {
        let listRaw = kk_array_list_of(0, 0)
        var thrown = 0
        _ = kk_mutable_list_add(listRaw, kk_box_char(55), &thrown)
        #expect(thrown == 0)
        let element: Int = switch elementType {
        case "Int": kk_box_int(6)
        case "Char": kk_box_char(54)
        default: runtimeNullSentinelInt
        }
        let replacesFirst = operation == "set" || operation == "iterator-set"
        switch operation {
        case "add":
            _ = kk_mutable_list_add(listRaw, element, &thrown)
        case "collection-add":
            _ = kk_mutable_collection_add_throwing(listRaw, element, &thrown)
        case "add-at":
            _ = kk_mutable_list_add_at(listRaw, 1, element, &thrown)
        case "set":
            _ = kk_mutable_list_set(listRaw, 0, element, &thrown)
        default:
            let iterator = kk_list_iterator(listRaw)
            _ = kk_list_iterator_next(iterator, &thrown)
            if replacesFirst {
                _ = runtimeListIteratorSet(iterator, element, &thrown)
            } else {
                _ = runtimeListIteratorAdd(iterator, element, &thrown)
            }
        }
        #expect(thrown == 0)
        let list = try #require(runtimeListBox(from: listRaw))
        #expect(list.count == (replacesFirst ? 1 : 2))
        let inserted = list.values[replacesFirst ? 0 : 1]
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
        if !replacesFirst {
            #expect(list.values[0].tag == RuntimeValue.charTag)
            #expect(list.values[0].payload0 == 55)
        }
    }
}
