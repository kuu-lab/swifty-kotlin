@testable import Runtime
import XCTest

final class RuntimeStringBuilderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // STDLIB-TEXT-FN-024: insert
    func testInsertObjInsertsValueAtIndexAndReturnsReceiver() {
        let builder = makeBuilder("ac")
        let value = makeRuntimeString("b")

        let returned = kk_string_builder_insert_obj(builder, 1, value)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testAppendRangeAppendsSubstringSliceAndReturnsReceiver() {
        let builder = makeBuilder("hello")
        let returned = withFlatString("WORLD") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 1, 4)
        }

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "helloORL")
    }

    func testAppendRangeFromEmptyRangeAppendsNothing() {
        let builder = makeBuilder("abc")
        let returned = withFlatString("XYZ") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 2, 2)
        }

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testAppendRangeUsesUTF16IndicesForMultibyteCharacters() {
        let builder = withFlatString("") { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let returned = withFlatString("你好世界") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 1, 3)
        }

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "好世")
    }

    func testInsertObjAtBeginningPrependsValue() {
        let builder = makeBuilder("bc")
        let value = makeRuntimeString("a")

        _ = kk_string_builder_insert_obj(builder, 0, value)

        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testInsertObjAtEndAppendsValue() {
        let builder = makeBuilder("ab")
        let value = makeRuntimeString("c")

        _ = kk_string_builder_insert_obj(builder, 2, value)

        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testDeleteAtRemovesCharacterAndReturnsReceiver() {
        let builder = makeBuilder("abc")
        var thrown = 0

        let returned = kk_string_builder_deleteAt(builder, 1, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "ac")
    }

    func testDeleteRangeRemovesRangeAndReturnsReceiver() {
        let builder = makeBuilder("abcdef")
        var thrown = 0

        let returned = kk_string_builder_deleteRange(builder, 1, 4, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aef")
    }

    func testInsertRangeInsertsValueSliceAndReturnsReceiver() {
        let builder = makeBuilder("ab")
        let value = makeRuntimeString("WXYZ")

        let returned = kk_string_builder_insertRange_obj(builder, 1, value, 1, 3)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYb")
    }

    func testSetRangeReplacesRangeAndReturnsReceiver() {
        let builder = makeBuilder("abcd")
        let value = makeRuntimeString("XYZ")

        let returned = kk_string_builder_setRange(builder, 1, 3, value)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYZd")
    }

    // STDLIB-TEXT-FN-064: operator fun set(index, value) — backed by kk_string_builder_setCharAt
    func testSetCharAtReplacesCharacterAtIndex() {
        let builder = makeBuilder("abc")
        var thrown = 0

        let returned = kk_string_builder_setCharAt(
            builder,
            1,
            kk_box_char(Int(Unicode.Scalar("X").value)),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXc")
    }

    func testSetCharAtFirstIndexReplacesCharacter() {
        let builder = makeBuilder("hello")
        var thrown = 0

        _ = kk_string_builder_setCharAt(
            builder,
            0,
            kk_box_char(Int(Unicode.Scalar("H").value)),
            &thrown
        )

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "Hello")
    }

    // STDLIB-TEXT-FN-004: appendLine
    func testAppendLineObjAppendsValueAndNewlineAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString(""))
        let value = makeRuntimeString("hello")

        let returned = kk_string_builder_append_line_obj(builder, value)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "hello\n")
    }

    func testAppendLineNoargAppendsNewlineAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("test"))

        let returned = kk_string_builder_append_line_noarg_obj(builder)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "test\n")
    }

    func testAppendLineObjChainingProducesCorrectString() {
        let builder = kk_string_builder_new()
        let a = makeRuntimeString("first")
        let b = makeRuntimeString("second")

        _ = kk_string_builder_append_line_obj(builder, a)
        _ = kk_string_builder_append_line_obj(builder, b)
        _ = kk_string_builder_append_line_noarg_obj(builder)

        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "first\nsecond\n\n")
    }

    func testAppendLineObjOnEmptyBuilderProducesJustNewline() {
        let builder = kk_string_builder_new()
        let value = makeRuntimeString("")

        _ = kk_string_builder_append_line_obj(builder, value)

        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "\n")
    }

    // DEBT-RT-001: out-of-bounds insert throws via outThrown instead of fatalError.
    func testInsertObjOutOfBoundsThrowsStringIndexOutOfBoundsException() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("hello"))
        let value = makeRuntimeString("x")
        var thrown = 0

        _ = kk_string_builder_insert_obj(builder, 99, value, &thrown)

        XCTAssertNotEqual(thrown, 0)
        let box = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(bitPattern: thrown)!)
            .takeUnretainedValue() as? RuntimeThrowableBox
        XCTAssertNotNil(box)
        XCTAssertTrue(
            box?.message.contains("index=99") ?? false,
            "expected index=99 in message, got: \(box?.message ?? "<nil>")"
        )
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "hello")
    }

    func testFlatStringBuilderAPIsUseFlattenedStringFields() {
        let builder = withFlatString("ac") { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let insertReturned = withFlatString("b") { data, length, byteCount, hash in
            kk_string_builder_insert_obj_flat(builder, 1, data, length, byteCount, hash)
        }
        XCTAssertEqual(insertReturned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")

        let appendReturned = withFlatString("D") { data, length, byteCount, hash in
            kk_string_builder_append_obj_flat(builder, data, length, byteCount, hash)
        }
        XCTAssertEqual(appendReturned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abcD")

        let appendLineReturned = withFlatString("E") { data, length, byteCount, hash in
            kk_string_builder_append_line_obj_flat(builder, data, length, byteCount, hash)
        }
        XCTAssertEqual(appendLineReturned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abcDE\n")

        let rangedBuilder = makeBuilder("hello")
        let appendRangeReturned = withFlatString("WORLD") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(rangedBuilder, data, length, byteCount, hash, 1, 4)
        }
        XCTAssertEqual(appendRangeReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "helloORL")

        let insertRangeReturned = withFlatString("abcd") { data, length, byteCount, hash in
            kk_string_builder_insertRange_obj_flat(rangedBuilder, 1, data, length, byteCount, hash, 1, 3)
        }
        XCTAssertEqual(insertRangeReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "hbcelloORL")

        let setRangeReturned = withFlatString("XY") { data, length, byteCount, hash in
            kk_string_builder_setRange_flat(rangedBuilder, 1, 3, data, length, byteCount, hash)
        }
        XCTAssertEqual(setRangeReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "hXYelloORL")

        let replaceReturned = withFlatString("Z") { data, length, byteCount, hash in
            kk_string_builder_replace_obj_flat(rangedBuilder, 1, 3, data, length, byteCount, hash)
        }
        XCTAssertEqual(replaceReturned, rangedBuilder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(rangedBuilder)), "hZelloORL")
    }

    func testAppendVarargUsesAggregateArgumentStorageWithoutLegacyStringBoxes() {
        let builder = makeBuilder("")
        let args = makeRuntimeValueArray([
            runtimeStringAggregateValue("left"),
            RuntimeValue(raw: kk_box_char(Int(Unicode.Scalar("-").value))),
            runtimeStringAggregateValue("right"),
        ])
        let baselineObjectCount = kk_debugging_global_object_count()

        let returned = kk_string_builder_append_vararg_obj(builder, args)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(
            kk_debugging_global_object_count(),
            baselineObjectCount,
            "StringBuilder.append(vararg) must not materialize RuntimeStringBox values from aggregate argument storage"
        )
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "left-right")
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
            XCTFail("Expected RuntimeArrayBox")
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
