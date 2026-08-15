#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeStringBuilderTests {
    @Test
    func testBridgeCreatesAppendsAndRendersStringBuilder() {
        let builder = __kk_string_builder_new()
        let returned = __kk_string_builder_append_obj(builder, makeRuntimeString("hello"))

        #expect(returned == builder)
        #expect(__kk_string_builder_length_prop(builder) == 5)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "hello")
    }

    // BUG-211: the CharSequence.length getter is an interface property. Runtime
    // StringBuilder objects must advertise its itable slot so bundled Kotlin
    // extensions can dispatch through the same path as user-defined classes.
    @Test
    func testCharSequenceLengthItableRegistrationForRuntimeObjects() {
        let builder = makeBuilder("abc")
        let string = makeRuntimeString("hello")
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        let getterRaw = kk_itable_lookup_dynamic(builder, interfaceTypeID, 0)
        let stringGetterRaw = kk_itable_lookup_dynamic(string, interfaceTypeID, 0)

        #expect(getterRaw != 0)
        #expect(stringGetterRaw != 0)

        let getter = unsafeBitCast(
            getterRaw,
            to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        #expect(getter(builder, &thrown) == 3)
        #expect(thrown == 0)
    }

    // BUG-211: temporary String boxes created through the low-level UTF-8
    // constructor must also participate in CharSequence.length dispatch.
    @Test
    func testUTF8StringConstructorRegistersCharSequenceLengthItable() {
        let bytes = Array("window".utf8)
        let raw = bytes.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        let getterRaw = kk_itable_lookup_dynamic(raw, interfaceTypeID, 0)

        #expect(getterRaw != 0)

        let getter = unsafeBitCast(
            getterRaw,
            to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var thrown = 0
        #expect(getter(raw, &thrown) == 6)
        #expect(thrown == 0)
    }

    @Test
    func testFlatConstructorAndFlatAppendUseFlattenedStringFields() {
        let builder = withFlatString("ab") { data, length, byteCount, hash in
            __kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
        }

        let returned = withFlatString("cd") { data, length, byteCount, hash in
            __kk_string_builder_append_obj_flat(builder, data, length, byteCount, hash)
        }

        #expect(returned == builder)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "abcd")
    }

    @Test
    func testClearResetsMutableBufferAndReturnsReceiver() {
        let builder = makeBuilder("abc")

        let returned = __kk_string_builder_clear(builder)

        #expect(returned == builder)
        #expect(__kk_string_builder_length_prop(builder) == 0)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "")
    }

    @Test
    func testAppendObjAcceptsStringRepresentations() {
        let builder = __kk_string_builder_new()

        _ = __kk_string_builder_append_obj(builder, makeRuntimeString("A"))
        _ = __kk_string_builder_append_obj(builder, makeRuntimeString("B"))

        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "AB")
    }

    private func makeRuntimeString(_ value: String) -> Int {
        registerRuntimeObject(RuntimeStringBox(value))
    }

    private func makeBuilder(_ value: String) -> Int {
        withFlatString(value) { data, length, byteCount, hash in
            __kk_string_builder_new_from_string_flat(data, length, byteCount, hash)
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
