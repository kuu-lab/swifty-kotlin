@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimePrimitiveArrayAsListTests {
    @Test func typedViewsReadAndWriteThroughBackingArray() throws {
        let cases: [(bridge: (Int) -> Int, box: (Int) -> Int, unbox: (Int) -> Int,
                     initial: Int, replacement: Int, rendered: String)] = [
            (kk_booleanArray_asList, kk_box_bool, kk_unbox_bool_static, 1, 0, "true"),
            (kk_charArray_asList, kk_box_char, kk_unbox_char_static, 97, 98, "a"),
            (kk_floatArray_asList, kk_box_float, kk_unbox_float_static,
             Int(Float(1.5).bitPattern), Int(Float(-0.0).bitPattern), "1.5"),
            (kk_doubleArray_asList, kk_box_double_nonnull, kk_unbox_double_nonnull_static,
             Int(bitPattern: UInt(Double(1.5).bitPattern)),
             Int(bitPattern: UInt(Double(-0.0).bitPattern)), "1.5"),
        ]
        for entry in cases {
            let array = RuntimeArrayBox(length: 2)
            array.elements = [entry.initial, entry.initial]
            let listRaw = entry.bridge(registerRuntimeObject(array))
            let list = try #require(runtimeListBox(from: listRaw))
            #expect(runtimeRenderAnyForPrint(listRaw) == "[\(entry.rendered), \(entry.rendered)]")
            #expect(entry.unbox(list[0]) == entry.initial)
            #expect(entry.unbox(list.values[0].legacyRawValue) == entry.initial)
            #expect(list.childRefs.isEmpty)

            let subList = RuntimeListBox(subListOf: list, fromIndex: 1, toIndex: 2)
            let reversed = RuntimeListBox(reversedViewOf: list)
            let iterator = kk_list_iterator(listRaw)
            array[0] = entry.replacement
            #expect(entry.unbox(kk_list_iterator_next(iterator, nil)) == entry.replacement)
            #expect(entry.unbox(reversed[1]) == entry.replacement)

            subList[0] = entry.box(entry.replacement)
            #expect(array.elements == [entry.replacement, entry.replacement])
            reversed.setValue(runtimeValueFromCollectionABI(entry.box(entry.initial)), at: 0)
            #expect(array[1] == entry.initial)
            list.values = [RuntimeValue(raw: entry.box(entry.initial)),
                           RuntimeValue(raw: entry.box(entry.replacement))]
            #expect(array.elements == [entry.initial, entry.replacement])
            #expect(entry.unbox(list[1]) == entry.replacement)

            let empty = try #require(runtimeListBox(from: entry.bridge(kk_array_new(0))))
            #expect(empty.values.isEmpty)
        }
    }

    @Test func genericArrayViewPreservesReferences() throws {
        let string = registerRuntimeObject(RuntimeStringBox("value"))
        let other = registerRuntimeObject(RuntimeStringBox("other"))
        let array = RuntimeArrayBox(length: 2)
        array.elements = [string, other]
        let list = try #require(runtimeListBox(from: kk_array_asList(registerRuntimeObject(array))))
        #expect(list[0] == string)
        #expect(list.childRefs == [string, other])
        #expect(RuntimeListBox(reversedViewOf: list).childRefs == [other, string])
        #expect(RuntimeListBox(subListOf: list, fromIndex: 0, toIndex: 1).childRefs == [string])
    }
}
