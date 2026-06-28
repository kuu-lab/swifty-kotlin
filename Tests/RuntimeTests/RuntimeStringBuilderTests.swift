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
        let builder = kk_string_builder_new_from_string(makeRuntimeString("ac"))
        let value = makeRuntimeString("b")
        var thrown = 0

        let returned = kk_string_builder_insert_obj(builder, 1, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testAppendRangeAppendsSubstringSliceAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("hello"))
        let value = makeRuntimeString("WORLD")

        let returned = kk_string_builder_appendRange_obj(builder, value, 1, 4)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "helloORL")
    }

    func testAppendRangeFromEmptyRangeAppendsNothing() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))
        let value = makeRuntimeString("XYZ")

        let returned = kk_string_builder_appendRange_obj(builder, value, 2, 2)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testAppendRangeUsesUTF16IndicesForMultibyteCharacters() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString(""))
        let value = makeRuntimeString("你好世界")

        let returned = kk_string_builder_appendRange_obj(builder, value, 1, 3)

        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "好世")
    }

    func testInsertObjAtBeginningPrependsValue() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("bc"))
        let value = makeRuntimeString("a")
        var thrown = 0

        _ = kk_string_builder_insert_obj(builder, 0, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testInsertObjAtEndAppendsValue() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("ab"))
        let value = makeRuntimeString("c")
        var thrown = 0

        _ = kk_string_builder_insert_obj(builder, 2, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "abc")
    }

    func testDeleteAtRemovesCharacterAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))
        var thrown = 0

        let returned = kk_string_builder_deleteAt(builder, 1, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "ac")
    }

    func testDeleteRangeRemovesRangeAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abcdef"))
        var thrown = 0

        let returned = kk_string_builder_deleteRange(builder, 1, 4, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aef")
    }

    func testInsertRangeInsertsValueSliceAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("ab"))
        let value = makeRuntimeString("WXYZ")
        var thrown = 0

        let returned = kk_string_builder_insertRange_obj(builder, 1, value, 1, 3, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYb")
    }

    func testSetRangeReplacesRangeAndReturnsReceiver() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abcd"))
        let value = makeRuntimeString("XYZ")
        var thrown = 0

        let returned = kk_string_builder_setRange(builder, 1, 3, value, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(returned, builder)
        XCTAssertEqual(runtimeStringValue(kk_string_builder_toString(builder)), "aXYZd")
    }

    // STDLIB-TEXT-FN-064: operator fun set(index, value) — backed by kk_string_builder_setCharAt
    func testSetCharAtReplacesCharacterAtIndex() {
        let builder = kk_string_builder_new_from_string(makeRuntimeString("abc"))
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
        let builder = kk_string_builder_new_from_string(makeRuntimeString("hello"))
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

    private func makeRuntimeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
