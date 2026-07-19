#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeStringBuilderTests {
    @Test
    func testBridgeCreatesAppendsAndRendersStringBuilder() {
        let builder = kk_string_builder_new()
        let returned = kk_string_builder_append_obj(builder, makeRuntimeString("hello"))

        #expect(returned == builder)
        #expect(kk_string_builder_length_prop(builder) == 5)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "hello")
    }

    @Test
    func testFlatConstructorAndFlatAppendUseFlattenedStringFields() {
        let builder = withFlatString("ab") { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let returned = withFlatString("cd") { data, length, byteCount, hash in
            kk_string_builder_append_obj_flat(builder, data, length, byteCount, hash)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "abcd")
    }

    @Test
    func testClearResetsMutableBufferAndReturnsReceiver() {
        let builder = makeBuilder("abc")

        let returned = kk_string_builder_clear(builder)

        #expect(returned == builder)
        #expect(kk_string_builder_length_prop(builder) == 0)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "")
    }

    @Test
    func testAppendableCompatibilityCharAppendUsesRawAndBoxedChars() {
        let builder = kk_string_builder_new()

        _ = kk_string_builder_append_char(builder, Int(Unicode.Scalar("A").value))
        _ = kk_string_builder_append_char(builder, kk_box_char(Int(Unicode.Scalar("B").value)))

        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "AB")
    }

    @Test
    func testAppendableCompatibilityRangeUsesUTF16Indices() {
        let builder = makeBuilder("hello")
        let returned = withFlatString("WORLD") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 1, 4)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "helloORL")
    }

    @Test
    func testAppendableCompatibilityRangeHandlesMultibyteCharacters() {
        let builder = kk_string_builder_new()
        let returned = withFlatString("你好世界") { data, length, byteCount, hash in
            kk_string_builder_appendRange_obj_flat(builder, data, length, byteCount, hash, 1, 3)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(kk_string_builder_toString(builder)) == "好世")
    }

    private func makeRuntimeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func makeBuilder(_ value: String) -> Int {
        withFlatString(value) { data, length, byteCount, hash in
            kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }
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
