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
            // KUU-4016: the integer views previously leaked raw words into
            // generic consumers (sorted()/Comparable, `is`, toString).
            (kk_intArray_asList, kk_box_int, kk_unbox_int, 41, -7, "41"),
            (kk_byteArray_asList, kk_box_byte, kk_unbox_int, 41, -7, "41"),
            (kk_shortArray_asList, kk_box_short, kk_unbox_int, 41, -7, "41"),
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

    /// KUU-4016: `IntArray.asList()` must hand boxed `Int` elements to generic
    /// consumers. `sorted()`/`sortedDescending()`/`List.sort()` reach them
    /// through a `Comparable` checkcast plus the erased `compareTo` dispatch,
    /// both of which a raw machine word cannot satisfy.
    @Test func integerViewsBoxElementsForComparableDispatch() throws {
        let comparableToken = nominalTypeToken(for: "kotlin.Comparable")
        let intToken = nominalTypeToken(for: "kotlin.Int")
        let array = RuntimeArrayBox(length: 2)
        array.elements = [3, 1]
        let listRaw = kk_intArray_asList(registerRuntimeObject(array))
        let list = try #require(runtimeListBox(from: listRaw))

        #expect(kk_op_is(list[0], comparableToken) == 1)
        #expect(kk_op_is(list[0], intToken) == 1)
        var thrown = 0
        #expect(__kk_comparable_compareTo(list[0], list[1], &thrown) > 0)
        #expect(__kk_comparable_compareTo(list[1], list[0], &thrown) < 0)
        #expect(thrown == 0)
    }

    /// The unsigned views sit on signed backing arrays whose storage is
    /// sign-extended: reads must box the logical unsigned payload while
    /// writes normalize back to the signed storage form.
    @Test func unsignedViewsBoxLogicalValuesOverSignedBackingStorage() throws {
        let ubytes = RuntimeArrayBox(length: 2)
        ubytes.elements = [-56, 1] // 200u, 1u
        let ubyteRaw = kk_uByteArray_asList(registerRuntimeObject(ubytes))
        let ubyteView = try #require(runtimeListBox(from: ubyteRaw))
        #expect(runtimeRenderAnyForPrint(ubyteRaw) == "[200, 1]")
        #expect(kk_unbox_int(ubyteView[0]) == 200)
        ubyteView[1] = kk_box_ubyte(201)
        #expect(ubytes.elements == [-56, -55])

        let ushorts = RuntimeArrayBox(length: 1)
        ushorts.elements = [-13031] // 52505u
        let ushortRaw = kk_uShortArray_asList(registerRuntimeObject(ushorts))
        let ushortView = try #require(runtimeListBox(from: ushortRaw))
        #expect(runtimeRenderAnyForPrint(ushortRaw) == "[52505]")
        #expect(kk_unbox_int(ushortView[0]) == 52505)
        ushortView[0] = kk_box_ushort(52506)
        #expect(ushorts.elements == [-13030])

        let uints = RuntimeArrayBox(length: 1)
        uints.elements = [-1] // 4294967295u
        let uintRaw = kk_uIntArray_asList(registerRuntimeObject(uints))
        let uintView = try #require(runtimeListBox(from: uintRaw))
        #expect(runtimeRenderAnyForPrint(uintRaw) == "[4294967295]")
        #expect(kk_unbox_int(uintView[0]) == 4294967295)
        uintView[0] = kk_box_uint(4294967294)
        #expect(uints.elements == [-2])

        let ulongs = RuntimeArrayBox(length: 1)
        ulongs.elements = [-1] // 18446744073709551615uL
        let ulongRaw = kk_uLongArray_asList(registerRuntimeObject(ulongs))
        let ulongView = try #require(runtimeListBox(from: ulongRaw))
        #expect(runtimeRenderAnyForPrint(ulongRaw) == "[18446744073709551615]")
        #expect(kk_unbox_ulong(ulongView[0]) == -1)
        ulongView[0] = kk_box_ulong_nonnull(-2)
        #expect(ulongs.elements == [-2])
    }

    @Test func genericArrayViewPreservesReferences() throws {
        let string = registerRuntimeObject(RuntimeStringBox("value"))
        let other = registerRuntimeObject(RuntimeStringBox("other"))
        let array = RuntimeArrayBox(length: 2)
        array.elements = [string, other]
        let listRaw = kk_array_asList(registerRuntimeObject(array))
        let list = try #require(runtimeListBox(from: listRaw))
        #expect(list[0] == string)
        #expect(list.childRefs == [string, other])
        // View storage retains the base box, so childRefs reports the base
        // pointer first (keeping it alive for GC/freeze) and then the base's
        // element refs in forward order.
        #expect(RuntimeListBox(reversedViewOf: list).childRefs == [listRaw, string, other])
        #expect(RuntimeListBox(subListOf: list, fromIndex: 0, toIndex: 1).childRefs == [listRaw, string, other])
    }
}
