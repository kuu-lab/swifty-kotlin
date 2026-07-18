#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeStringBuilderTests {
    init() {
        kk_runtime_force_reset()
    }

    // STDLIB-TEXT-FN-024: insert
    @Test
    func testInsertObjInsertsValueAtIndexAndReturnsReceiver() {
        let builder = makeBuilder("ac")
        let value = makeRuntimeString("b")

        let returned = kk_string_builder_insert_obj(builder, 1, value)

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abc")
    }

    @Test
    func testAppendRangeAppendsSubstringSliceAndReturnsReceiver() {
        let builder = makeBuilder("hello")
        let returned = withFlatString("WORLD") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 1, 4)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "helloORL")
    }

    @Test
    func testAppendRangeFromEmptyRangeAppendsNothing() {
        let builder = makeBuilder("abc")
        let returned = withFlatString("XYZ") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 2, 2)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abc")
    }

    @Test
    func testAppendRangeUsesUTF16IndicesForMultibyteCharacters() {
        let builder = withFlatString("") { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let returned = withFlatString("你好世界") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 1, 3)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "好世")
    }

    @Test
    func testInsertObjAtBeginningPrependsValue() {
        let builder = makeBuilder("bc")
        let value = makeRuntimeString("a")

        _ = kk_string_builder_insert_obj(builder, 0, value)

        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abc")
    }

    @Test
    func testInsertObjAtEndAppendsValue() {
        let builder = makeBuilder("ab")
        let value = makeRuntimeString("c")

        _ = kk_string_builder_insert_obj(builder, 2, value)

        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abc")
    }

    @Test
    func testDeleteAtRemovesCharacterAndReturnsReceiver() {
        let builder = makeBuilder("abc")
        var thrown = 0

        let returned = kk_string_builder_deleteAt(builder, 1, &thrown)

        #expect(thrown == 0)
        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "ac")
    }

    @Test
    func testDeleteRangeRemovesRangeAndReturnsReceiver() {
        let builder = makeBuilder("abcdef")
        var thrown = 0

        let returned = kk_string_builder_deleteRange(builder, 1, 4, &thrown)

        #expect(thrown == 0)
        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "aef")
    }

    @Test
    func testInsertRangeInsertsValueSliceAndReturnsReceiver() {
        let builder = makeBuilder("ab")
        let value = makeRuntimeString("WXYZ")

        let returned = kk_string_builder_insertRange_obj(builder, 1, value, 1, 3)

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "aXYb")
    }

    @Test
    func testSetRangeReplacesRangeAndReturnsReceiver() {
        let builder = makeBuilder("abcd")
        let value = makeRuntimeString("XYZ")

        let returned = kk_string_builder_setRange(builder, 1, 3, value)

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "aXYZd")
    }

    // STDLIB-TEXT-FN-064: operator fun set(index, value) — backed by kk_string_builder_setCharAt
    @Test
    func testSetCharAtReplacesCharacterAtIndex() {
        let builder = makeBuilder("abc")
        var thrown = 0

        let returned = kk_string_builder_setCharAt(
            builder,
            1,
            kk_box_char(Int(Unicode.Scalar("X").value)),
            &thrown
        )

        #expect(thrown == 0)
        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "aXc")
    }

    @Test
    func testSetCharAtFirstIndexReplacesCharacter() {
        let builder = makeBuilder("hello")
        var thrown = 0

        _ = kk_string_builder_setCharAt(
            builder,
            0,
            kk_box_char(Int(Unicode.Scalar("H").value)),
            &thrown
        )

        #expect(thrown == 0)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "Hello")
    }

    // STDLIB-TEXT-FN-004: appendLine
    @Test
    func testAppendLineObjAppendsValueAndNewlineAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString(""))
        let value = makeRuntimeString("hello")

        let returned = kk_string_builder_append_line_obj(builder, value)

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "hello\n")
    }

    @Test
    func testAppendLineNoargAppendsNewlineAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("test"))

        let returned = kk_string_builder_append_line_noarg_obj(builder)

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "test\n")
    }

    @Test
    func testAppendLineObjChainingProducesCorrectString() {
        let builder = kk_string_builder_new()
        let a = makeRuntimeString("first")
        let b = makeRuntimeString("second")

        _ = kk_string_builder_append_line_obj(builder, a)
        _ = kk_string_builder_append_line_obj(builder, b)
        _ = kk_string_builder_append_line_noarg_obj(builder)

        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "first\nsecond\n\n")
    }

    @Test
    func testAppendLineObjOnEmptyBuilderProducesJustNewline() {
        let builder = kk_string_builder_new()
        let value = makeRuntimeString("")

        _ = kk_string_builder_append_line_obj(builder, value)

        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "\n")
    }

    // DEBT-RT-001: out-of-bounds insert throws via outThrown instead of fatalError.
    @Test
    func testInsertObjOutOfBoundsThrowsStringIndexOutOfBoundsException() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("hello"))
        let value = makeRuntimeString("x")
        var thrown = 0

        _ = kk_string_builder_insert_obj(builder, 99, value, &thrown)

        #expect(thrown != 0)
        let box = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: thrown)!)
            .takeUnretainedValue() as? RuntimeThrowableBox
        #expect(box != nil)
        #expect(box is RuntimeStringIndexOutOfBoundsExceptionBox)
        #expect(box?.exceptionFQName == "kotlin.StringIndexOutOfBoundsException")
        #expect(box?.exceptionHierarchyFQNames.contains("kotlin.IndexOutOfBoundsException") ?? false)
        #expect(
            box?.message.contains("index=99") ?? false,
            "expected index=99 in message, got: \(box?.message ?? "<nil>")"
        )
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "hello")
    }

    @Test
    func testFlatStringBuilderAPIsUseFlattenedStringFields() {
        let builder = withFlatString("ac") { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let insertReturned = withFlatString("b") { data, length, byteCount, hash in
            kk_string_builder_insert_obj_flat(builder, 1, data, length, byteCount, hash)
        }
        #expect(insertReturned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abc")

        let appendReturned = withFlatString("D") { data, length, byteCount, hash in
            kk_string_builder_append_obj_flat(builder, data, length, byteCount, hash)
        }
        #expect(appendReturned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abcD")

        let appendLineReturned = withFlatString("E") { data, length, byteCount, hash in
            kk_string_builder_append_line_obj_flat(builder, data, length, byteCount, hash)
        }
        #expect(appendLineReturned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abcDE\n")

        let rangedBuilder = makeBuilder("hello")
        let appendRangeReturned = withFlatString("WORLD") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(rangedBuilder, data, length, byteCount, hash, 1, 4)
        }
        #expect(appendRangeReturned == rangedBuilder)
        #expect(runtimeStringValue(kk_string_builder_toString(rangedBuilder)) == "helloORL")

        let insertRangeReturned = withFlatString("abcd") { data, length, byteCount, hash in
            kk_string_builder_insertRange_obj_flat(rangedBuilder, 1, data, length, byteCount, hash, 1, 3)
        }
        #expect(insertRangeReturned == rangedBuilder)
        #expect(runtimeStringValue(kk_string_builder_toString(rangedBuilder)) == "hbcelloORL")

        let setRangeReturned = withFlatString("XY") { data, length, byteCount, hash in
            kk_string_builder_setRange_flat(rangedBuilder, 1, 3, data, length, byteCount, hash)
        }
        #expect(setRangeReturned == rangedBuilder)
        #expect(runtimeStringValue(kk_string_builder_toString(rangedBuilder)) == "hXYelloORL")

        let replaceReturned = withFlatString("Z") { data, length, byteCount, hash in
            kk_string_builder_replace_obj_flat(rangedBuilder, 1, 3, data, length, byteCount, hash)
        }
        #expect(replaceReturned == rangedBuilder)
        #expect(runtimeStringValue(kk_string_builder_toString(rangedBuilder)) == "hZelloORL")
    }

    @Test
    func testAppendVarargUsesAggregateArgumentStorageWithoutLegacyStringBoxes() {
        let builder = makeBuilder("")
        let args = makeRuntimeValueArray([
            runtimeStringAggregateValue("left"),
            RuntimeValue(raw: kk_box_char(Int(Unicode.Scalar("-").value))),
            runtimeStringAggregateValue("right"),
        ])
        let baselineObjectCount = kk_debugging_global_object_count()

        let returned = kk_string_builder_append_vararg_obj(builder, args)

        #expect(returned == builder)
        #expect(
            kk_debugging_global_object_count() == baselineObjectCount,
            "StringBuilder.append(vararg) must not materialize RuntimeStringBox values from aggregate argument storage"
        )
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "left-right")
    }

    private func makeRuntimeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func makeBuilder(_ value: String) -> Int {
        withFlatString(value) { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }
    }

    private func makeRuntimeValueArray(_ values: [RuntimeValue]) -> Int {
        let array = kk_array_new(values.count)
        guard let box = runtimeArrayBox(from: array) else {
            Issue.record("Expected RuntimeArrayBox")
            return array
        }
        box.values = values
        return array
    }

    private func runtimeStringAggregateValue(_ value: String) -> RuntimeValue {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = runtimeRegisterFlatString(
            value,
            outLength: &length,
            outByteCount: &byteCount,
            outHash: &hash
        )
        return RuntimeValue(
            stringData: data.map { Int(bitPattern: $0) } ?? 0,
            length: length,
            byteCount: byteCount,
            hash: hash
        )
    }

    private func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        Array(value.utf8).withUnsafeBufferPointer { buffer in
            body(buffer.baseAddress, value.unicodeScalars.count, value.utf8.count, 0)
        }
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
#endif
