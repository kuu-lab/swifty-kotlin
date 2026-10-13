#if canImport(Testing)
import Testing
@testable import Runtime

private final class CountingCharSequenceBox {
    let length: Int
    var lengthCalls = 0
    var getCalls = 0
    var getThrown = 0

    init(length: Int, getThrown: Int = 0) {
        self.length = length
        self.getThrown = getThrown
    }
}

private final class CharSequenceDefaultValueBox {
    let value: Int
    let thrown: Int
    var calls = 0

    init(value: Int, thrown: Int = 0) {
        self.value = value
        self.thrown = thrown
    }
}

private let countingCharSequenceGet: @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, index, outThrown in
    guard let box = resolveRuntimeHandle(raw, as: CountingCharSequenceBox.self) else {
        outThrown?.pointee = 0
        return 0
    }
    box.getCalls += 1
    outThrown?.pointee = box.getThrown
    return 97 + index
}

private let countingCharSequenceLength: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, outThrown in
    guard let box = resolveRuntimeHandle(raw, as: CountingCharSequenceBox.self) else {
        outThrown?.pointee = 0
        return 0
    }
    box.lengthCalls += 1
    outThrown?.pointee = 0
    return box.length
}

private let charSequenceDefaultValue: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = {
    raw, outThrown in
    guard let box = resolveRuntimeHandle(raw, as: CharSequenceDefaultValueBox.self) else {
        outThrown?.pointee = 0
        return 0
    }
    box.calls += 1
    outThrown?.pointee = box.thrown
    return box.value
}

@Suite(.serialized)
struct RuntimeCharSequenceIfEmptyTests {
    @Test
    func testCustomCharSequenceUsesLengthWithoutCallingGet() {
        let receiver = makeCharSequence(length: 3, getThrown: runtimeAllocateIllegalStateException(message: "get must not run"))
        let fallback = makeDefaultValue(value: runtimeMakeStringRaw("fallback"))
        var thrown = -1

        let result = kk_charsequence_ifEmpty(
            receiver.raw,
            unsafeBitCast(charSequenceDefaultValue, to: Int.self),
            fallback.raw,
            &thrown
        )

        #expect(result == receiver.raw)
        #expect(thrown == 0)
        #expect(receiver.box.lengthCalls == 1)
        #expect(receiver.box.getCalls == 0)
        #expect(fallback.box.calls == 0)
    }

    @Test
    func testEmptyCustomCharSequenceRunsDefaultAndPropagatesItsException() {
        let receiver = makeCharSequence(length: 0)
        let fallback = runtimeMakeStringRaw("fallback")
        let defaultValue = makeDefaultValue(value: fallback)
        var thrown = -1

        let result = kk_charsequence_ifEmpty(
            receiver.raw,
            unsafeBitCast(charSequenceDefaultValue, to: Int.self),
            defaultValue.raw,
            &thrown
        )

        #expect(result == fallback)
        #expect(thrown == 0)
        #expect(receiver.box.lengthCalls == 1)
        #expect(receiver.box.getCalls == 0)
        #expect(defaultValue.box.calls == 1)

        let exception = runtimeAllocateIllegalStateException(message: "default failed")
        let throwingDefault = makeDefaultValue(value: 0, thrown: exception)
        var defaultThrown = 0
        let throwingResult = kk_charsequence_ifEmpty(
            receiver.raw,
            unsafeBitCast(charSequenceDefaultValue, to: Int.self),
            throwingDefault.raw,
            &defaultThrown
        )

        #expect(throwingResult == 0)
        #expect(defaultThrown == exception)
        #expect(receiver.box.lengthCalls == 2)
        #expect(receiver.box.getCalls == 0)
        #expect(throwingDefault.box.calls == 1)
    }

    @Test
    func testStringBuilderAndInvalidHandles() {
        let emptyBuilder = __kk_string_builder_new()
        let fallback = runtimeMakeStringRaw("fallback")
        let defaultValue = makeDefaultValue(value: fallback)
        var thrown = -1

        let emptyResult = kk_charsequence_ifEmpty(
            emptyBuilder,
            unsafeBitCast(charSequenceDefaultValue, to: Int.self),
            defaultValue.raw,
            &thrown
        )
        #expect(emptyResult == fallback)
        #expect(thrown == 0)
        #expect(defaultValue.box.calls == 1)

        let nonEmptyBuilder = __kk_string_builder_new()
        _ = __kk_string_builder_append_obj(nonEmptyBuilder, runtimeMakeStringRaw("abc"))
        let nonEmptyResult = kk_charsequence_ifEmpty(
            nonEmptyBuilder,
            unsafeBitCast(charSequenceDefaultValue, to: Int.self),
            defaultValue.raw,
            &thrown
        )
        #expect(nonEmptyResult == nonEmptyBuilder)
        #expect(thrown == 0)
        #expect(defaultValue.box.calls == 1)

        for invalidHandle in [0, runtimeNullSentinelInt, 1] {
            thrown = -1
            let invalidResult = kk_charsequence_ifEmpty(
                invalidHandle,
                unsafeBitCast(charSequenceDefaultValue, to: Int.self),
                defaultValue.raw,
                &thrown
            )
            #expect(invalidResult == 0)
            #expect(thrown == 0)
        }
        #expect(defaultValue.box.calls == 1)
    }

    private func makeCharSequence(
        length: Int,
        getThrown: Int = 0
    ) -> (raw: Int, box: CountingCharSequenceBox) {
        let box = CountingCharSequenceBox(length: length, getThrown: getThrown)
        let raw = registerRuntimeObject(box)
        let interfaceTypeID = Int(runtimeStableNominalTypeID(fqName: "kotlin.CharSequence"))
        _ = kk_object_register_itable_iface(raw, interfaceTypeID, 0)
        _ = kk_object_register_itable_method(
            raw,
            0,
            0,
            unsafeBitCast(countingCharSequenceGet, to: Int.self)
        )
        _ = kk_object_register_itable_method(
            raw,
            0,
            2,
            unsafeBitCast(countingCharSequenceLength, to: Int.self)
        )
        return (raw, box)
    }

    private func makeDefaultValue(
        value: Int,
        thrown: Int = 0
    ) -> (raw: Int, box: CharSequenceDefaultValueBox) {
        let box = CharSequenceDefaultValueBox(value: value, thrown: thrown)
        return (registerRuntimeObject(box), box)
    }
}
#endif
