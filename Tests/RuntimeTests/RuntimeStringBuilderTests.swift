#if canImport(Testing)
import Testing
@testable import Runtime

@Suite(.serialized)
struct RuntimeStringBuilderTests {
    @Test(arguments: [0, 1, 16, 100, 200])
    func testCapacityConstructorReservesRequestedStorage(capacity: Int) {
        var thrown = 123
        let builder = __kk_string_builder_new_capacity_checked(capacity, &thrown)

        #expect(thrown == 0)
        #expect(__kk_string_builder_capacity(builder) == capacity)
        #expect(__kk_string_builder_length_prop(builder) == 0)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "")

        let box = RuntimeStringBuilderBox(units: [], capacity: capacity)
        #expect(box.units.capacity >= capacity)
    }

    @Test
    func testNegativeCapacityStillThrows() {
        var thrown = 0
        #expect(__kk_string_builder_new_capacity_checked(-1, &thrown) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testEnsureCapacityGrowsWithoutChangingContents() {
        let builder = __kk_string_builder_new()
        #expect(__kk_string_builder_capacity(builder) == 16)
        _ = __kk_string_builder_append_obj(builder, makeRuntimeString("abc"))
        _ = __kk_string_builder_ensure_capacity(builder, 200)
        #expect(__kk_string_builder_capacity(builder) == 200)
        for requested in [-1, 0, 100, 200] {
            _ = __kk_string_builder_ensure_capacity(builder, requested)
            #expect(__kk_string_builder_capacity(builder) == 200)
        }
        #expect(__kk_string_builder_length_prop(builder) == 3)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "abc")

        let box = RuntimeStringBuilderBox("abc")
        box.ensureCapacity(200)
        #expect(box.capacity == 200)
        #expect(box.units.capacity >= 200)
        #expect(box.stringValue == "abc")
    }

    @Test
    func testGrowthAndTrimUseUTF16Capacity() {
        let builder = __kk_string_builder_new()
        _ = __kk_string_builder_append_obj(builder, makeRuntimeString(String(repeating: "a", count: 20)))
        #expect(__kk_string_builder_capacity(builder) == 34)
        _ = __kk_string_builder_clear(builder)
        #expect(__kk_string_builder_capacity(builder) == 34)
        _ = __kk_string_builder_append_obj(builder, makeRuntimeString("a😀b"))
        _ = __kk_string_builder_trim_to_size(builder)
        #expect(__kk_string_builder_capacity(builder) == 4)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "a😀b")
        _ = __kk_string_builder_append_char(builder, 99)
        #expect(__kk_string_builder_capacity(builder) == 10)
        _ = __kk_string_builder_clear(builder)
        _ = __kk_string_builder_trim_to_size(builder)
        #expect(__kk_string_builder_capacity(builder) == 0)
        _ = __kk_string_builder_append_char(builder, 120)
        #expect(__kk_string_builder_capacity(builder) == 2)
    }

    @Test
    func testStringAndCharSequenceConstructorsIncludeUTF16Slack() {
        let builder = makeBuilder("a😀b")
        #expect(__kk_string_builder_capacity(builder) == 20)
        let copied = __kk_string_builder_new_from_char_sequence(builder)
        #expect(__kk_string_builder_capacity(copied) == 20)
        #expect(runtimeStringValue(__kk_string_builder_toString(copied)) == "a😀b")
    }

    @Test
    func testInsertAndSetLengthGrowAndRetainCapacity() {
        var thrown = 0
        let builder = __kk_string_builder_new_capacity_checked(2, &thrown)
        _ = __kk_string_builder_append_obj(builder, makeRuntimeString("ab"))
        _ = __kk_string_builder_insert_char_sequence(builder, 1, builder, &thrown)
        #expect(thrown == 0)
        #expect(__kk_string_builder_capacity(builder) == 6)
        _ = __kk_string_builder_set_length(builder, 20, &thrown)
        #expect(thrown == 0)
        #expect(__kk_string_builder_capacity(builder) == 20)
        #expect(__kk_string_builder_length_prop(builder) == 20)
        _ = __kk_string_builder_set_length(builder, 1, &thrown)
        #expect(__kk_string_builder_capacity(builder) == 20)
    }

    @Test
    func testBridgeCreatesAppendsAndRendersStringBuilder() {
        let builder = __kk_string_builder_new()
        let returned = __kk_string_builder_append_obj(builder, makeRuntimeString("hello"))

        #expect(returned == builder)
        #expect(__kk_string_builder_length_prop(builder) == 5)
        #expect(runtimeStringValue(__kk_string_builder_toString(builder)) == "hello")
    }

    // KSP-817: runtime-backed CharSequence values must expose the same method
    // and property slots as source-defined implementations.
    @Test
    func testCharSequenceItableRegistrationForRuntimeObjects() {
        let builder = makeBuilder("abc")
        let string = makeRuntimeString("hello")
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        let getRaw = kk_itable_lookup_dynamic(builder, interfaceTypeID, 0)
        let stringGetRaw = kk_itable_lookup_dynamic(string, interfaceTypeID, 0)
        let subSequenceRaw = kk_itable_lookup_dynamic(builder, interfaceTypeID, 1)
        let stringSubSequenceRaw = kk_itable_lookup_dynamic(string, interfaceTypeID, 1)
        let lengthRaw = kk_itable_lookup_dynamic(builder, interfaceTypeID, 2)
        let stringLengthRaw = kk_itable_lookup_dynamic(string, interfaceTypeID, 2)

        #expect(getRaw != 0)
        #expect(stringGetRaw != 0)
        #expect(subSequenceRaw != 0)
        #expect(stringSubSequenceRaw != 0)
        #expect(lengthRaw != 0)
        #expect(stringLengthRaw != 0)

        let get = unsafeBitCast(
            getRaw,
            to: (@convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var getThrown = 0
        #expect(get(builder, 1, &getThrown) == 98)
        #expect(getThrown == 0)

        let length = unsafeBitCast(
            lengthRaw,
            to: (@convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var lengthThrown = 0
        #expect(length(builder, &lengthThrown) == 3)
        #expect(lengthThrown == 0)

        let subSequence = unsafeBitCast(
            subSequenceRaw,
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var subSequenceThrown = 0
        let suffix = subSequence(builder, 1, 3, &subSequenceThrown)
        #expect(subSequenceThrown == 0)
        #expect(runtimeStringValue(suffix) == "bc")

        let stringSubSequence = unsafeBitCast(
            stringSubSequenceRaw,
            to: (@convention(c) (Int, Int, Int, UnsafeMutablePointer<Int>?) -> Int).self
        )
        var stringSubSequenceThrown = 0
        let stringSuffix = stringSubSequence(string, 1, 5, &stringSubSequenceThrown)
        #expect(stringSubSequenceThrown == 0)
        #expect(runtimeStringValue(stringSuffix) == "ello")

        let empty = makeRuntimeString("")
        var emptyLengthThrown = 0
        #expect(length(empty, &emptyLengthThrown) == 0)
        #expect(emptyLengthThrown == 0)
        var emptySubSequenceThrown = 0
        let emptySubSequence = subSequence(empty, 0, 0, &emptySubSequenceThrown)
        #expect(emptySubSequenceThrown == 0)
        #expect(runtimeStringValue(emptySubSequence) == "")

        var invalidRangeThrown = 0
        _ = subSequence(string, 2, 1, &invalidRangeThrown)
        #expect(invalidRangeThrown != 0)

        let emojiBuilder = makeBuilder("🥦")
        let emojiString = makeRuntimeString("🥦")
        var emojiBuilderGetThrown = 0
        var emojiStringGetThrown = 0
        #expect(get(emojiBuilder, 0, &emojiBuilderGetThrown) == 55358)
        #expect(get(emojiBuilder, 1, &emojiBuilderGetThrown) == 56678)
        #expect(get(emojiString, 0, &emojiStringGetThrown) == 55358)
        #expect(get(emojiString, 1, &emojiStringGetThrown) == 56678)
        #expect(emojiBuilderGetThrown == 0)
        #expect(emojiStringGetThrown == 0)
    }

    // KSP-817: temporary String boxes created through the low-level UTF-8
    // constructor must also participate in CharSequence.length dispatch.
    @Test
    func testUTF8StringConstructorRegistersCharSequenceItable() {
        let bytes = Array("window".utf8)
        let raw = bytes.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        let getterRaw = kk_itable_lookup_dynamic(raw, interfaceTypeID, 2)

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
