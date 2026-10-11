#if canImport(Testing)
@testable import Runtime
import Testing
import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private typealias RuntimeStringUnaryEntry = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int
typealias RuntimeFlatStringReturnEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
typealias RuntimeFlatStringReturnWithIntEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
private typealias RuntimeFlatStringReturnWithIntNoThrowEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
typealias RuntimeFlatStringReturnWithIntCharEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
typealias RuntimeFlatStringReturnWithThreeIntsEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
typealias RuntimeFlatStringReturnWithTwoIntsEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
typealias RuntimeFlatStringReturnWithTwoStringsBoolEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
typealias RuntimeFlatStringReturnWithLeadingIntAndIntEntry = (
    Int,
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?

private let runtimeFlatStringLengthTransform: RuntimeStringUnaryEntry = { _, strRaw, _ in
    runtimeStringFromRawOrPanic(strRaw, caller: "runtimeFlatStringLengthTransform").count
}

private let runtimeReturnValueTransform: RuntimeStringUnaryEntry = { _, valueRaw, _ in
    valueRaw
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeStringArrayTests {

    func withFlatString<T>(
        _ value: String,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        var length = 0
        var byteCount = 0
        var hash = 0
        let data = runtimeRegisterFlatString(
            value,
            outLength: &length,
            outByteCount: &byteCount,
            outHash: &hash
        )
        let constData = data.map { UnsafePointer($0) }
        return body(constData, length, byteCount, hash)
    }

    private func withOptionalFlatString<T>(
        _ value: String?,
        _ body: (UnsafePointer<UInt8>?, Int, Int, Int) -> T
    ) -> T {
        guard let value else {
            return body(nil, 0, 0, 0)
        }
        return withFlatString(value, body)
    }

    private func concatFlatValue(_ lhs: String?, _ rhs: String?) -> String {
        withOptionalFlatString(lhs) { lhsData, lhsLength, lhsByteCount, lhsHash in
            withOptionalFlatString(rhs) { rhsData, rhsLength, rhsByteCount, rhsHash in
                var outLength = 0
                var outByteCount = 0
                var outHash = 0
                let resultData = __kk_string_concat_flat(
                    lhsData,
                    lhsLength,
                    lhsByteCount,
                    lhsHash,
                    rhsData,
                    rhsLength,
                    rhsByteCount,
                    rhsHash,
                    &outLength,
                    &outByteCount,
                    &outHash
                )
                return flatStringValue(
                    data: resultData.map { UnsafePointer($0) },
                    length: outLength,
                    byteCount: outByteCount,
                    hash: outHash
                )
            }
        }
    }

    func flatStringValue(
        data: UnsafePointer<UInt8>?,
        length: Int,
        byteCount: Int,
        hash: Int
    ) -> String {
        runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    }

    func flatStringReturnValue(
        _ value: String,
        using call: RuntimeFlatStringReturnEntry
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(data, length, byteCount, hash, &outLength, &outByteCount, &outHash)
            return flatStringValue(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    func flatStringReturnValue(
        _ value: String,
        intArg: Int,
        using call: RuntimeFlatStringReturnWithIntEntry,
        outThrown: UnsafeMutablePointer<Int>? = nil
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(data, length, byteCount, hash, intArg, &outLength, &outByteCount, &outHash, outThrown)
            return flatStringValue(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    func flatStringReturnValue(
        _ value: String,
        leadingIntArg: Int,
        trailingIntArg: Int,
        using call: RuntimeFlatStringReturnWithLeadingIntAndIntEntry,
        outThrown: UnsafeMutablePointer<Int>? = nil
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(
                leadingIntArg,
                data,
                length,
                byteCount,
                hash,
                trailingIntArg,
                &outLength,
                &outByteCount,
                &outHash,
                outThrown
            )
            return flatStringValue(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    func flatStringReturnValue(
        _ value: String,
        first: String,
        second: String,
        ignoreCase: Bool,
        using call: RuntimeFlatStringReturnWithTwoStringsBoolEntry
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            withFlatString(first) { firstData, firstLength, firstByteCount, firstHash in
                withFlatString(second) { secondData, secondLength, secondByteCount, secondHash in
                    var outLength = 0
                    var outByteCount = 0
                    var outHash = 0
                    let outData = call(
                        data,
                        length,
                        byteCount,
                        hash,
                        firstData,
                        firstLength,
                        firstByteCount,
                        firstHash,
                        secondData,
                        secondLength,
                        secondByteCount,
                        secondHash,
                        ignoreCase ? 1 : 0,
                        &outLength,
                        &outByteCount,
                        &outHash
                    )
                    return flatStringValue(
                        data: outData.map { UnsafePointer($0) },
                        length: outLength,
                        byteCount: outByteCount,
                        hash: outHash
                    )
                }
            }
        }
    }

    func flatStringReturnValue(
        _ value: String,
        intArg: Int,
        charArg: Int,
        using call: RuntimeFlatStringReturnWithIntCharEntry
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(data, length, byteCount, hash, intArg, charArg, &outLength, &outByteCount, &outHash)
            return flatStringValue(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    func flatStringReturnValue(
        _ value: String,
        firstIntArg: Int,
        secondIntArg: Int,
        thirdIntArg: Int,
        using call: RuntimeFlatStringReturnWithThreeIntsEntry
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(
                data,
                length,
                byteCount,
                hash,
                firstIntArg,
                secondIntArg,
                thirdIntArg,
                &outLength,
                &outByteCount,
                &outHash
            )
            return flatStringValue(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    func flatStringReturnValue(
        _ value: String,
        firstIntArg: Int,
        secondIntArg: Int,
        using call: RuntimeFlatStringReturnWithTwoIntsEntry,
        outThrown: UnsafeMutablePointer<Int>? = nil
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(
                data,
                length,
                byteCount,
                hash,
                firstIntArg,
                secondIntArg,
                &outLength,
                &outByteCount,
                &outHash,
                outThrown
            )
            return flatStringValue(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    // MARK: - kk_string_from_utf8

    @Test
    func testStringFromUTF8CreatesBoxedString() {
        let text = "Hello"
        let result = text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                kk_string_from_utf8(ptr, Int32(text.utf8.count))
            }
        }
        #expect(result as UnsafeMutableRawPointer? != nil)
        // Verify via println
        let output = capturePrintln { kk_println_any(result) }
        #expect(output == "Hello")
    }

    @Test
    func testStringFromUTF8EmptyString() {
        let text = ""
        let result = text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: 1) { ptr in
                kk_string_from_utf8(ptr, 0)
            }
        }
        #expect(result as UnsafeMutableRawPointer? != nil)
        let output = capturePrintln { kk_println_any(result) }
        #expect(output == "")
    }

    // MARK: - __kk_string_concat_flat

    @Test
    func testStringConcatFlatTwoStrings() {
        #expect(concatFlatValue("Hello, ", "World!") == "Hello, World!")
    }

    // BUG-B: a nil data pointer is the flat ABI's unambiguous signal for an
    // actually-null String -- a genuinely empty string ("") always has a
    // non-nil buffer. String templates and `+`/`String?.plus` must render a
    // null operand as the text "null", matching every other Kotlin
    // reference type, instead of silently treating it as "" (which hid an
    // uninitialized-field bug behind output that merely looked wrong
    // instead of null -- see null_string_length_npe.kt).

    @Test
    func testStringConcatFlatWithNilDataLeftRendersNullPrefix() {
        #expect(concatFlatValue(nil, "World") == "nullWorld")
    }

    @Test
    func testStringConcatFlatWithNilDataRightRendersNullSuffix() {
        #expect(concatFlatValue("Hello", nil) == "Hellonull")
    }

    @Test
    func testStringConcatFlatBothNilDataReturnsNullNull() {
        #expect(concatFlatValue(nil, nil) == "nullnull")
    }

    // MARK: - kk_string_compareTo_flat

    @Test
    func testStringCompareToFlatEqual() {
        withFlatString("abc") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("abc") { rhsData, rhsLength, rhsByteCount, rhsHash in
                #expect(kk_string_compareTo_flat(
                        lhsData,
                        lhsLength,
                        lhsByteCount,
                        lhsHash,
                        rhsData,
                        rhsLength,
                        rhsByteCount,
                        rhsHash
                    ) == 0)
            }
        }
    }

    @Test
    func testStringCompareToFlatLessThan() {
        withFlatString("abc") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("xyz") { rhsData, rhsLength, rhsByteCount, rhsHash in
                #expect(kk_string_compareTo_flat(
                        lhsData,
                        lhsLength,
                        lhsByteCount,
                        lhsHash,
                        rhsData,
                        rhsLength,
                        rhsByteCount,
                        rhsHash
                    ) == -23)
            }
        }
    }

    @Test
    func testStringCompareToFlatGreaterThan() {
        withFlatString("xyz") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("abc") { rhsData, rhsLength, rhsByteCount, rhsHash in
                #expect(kk_string_compareTo_flat(
                        lhsData,
                        lhsLength,
                        lhsByteCount,
                        lhsHash,
                        rhsData,
                        rhsLength,
                        rhsByteCount,
                        rhsHash
                    ) == 23)
            }
        }
    }

    @Test
    func testStringCompareToFlatNullDataAsEmpty() {
        #expect(kk_string_compareTo_flat(nil, 0, 0, 0, nil, 0, 0, 0) == 0)
    }

    @Test
    func testCompareAnyDecodesBoxedDoubleValues() {
        let lhs = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 1.25.bitPattern)))
        let rhs = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern)))

        #expect(kk_compare_any(lhs, rhs) == -1)
        #expect(kk_compare_any(rhs, lhs) == 1)
    }

    @Test
    func testCompareAnyPromotesMixedFloatingAndIntegerValues() {
        let lhs = kk_box_float(Int(Float(3).bitPattern))

        #expect(kk_compare_any(lhs, 5) == -1)
        #expect(kk_compare_any(5, lhs) == 1)
        #expect(kk_compare_any(lhs, 3) == 0)
    }

    @Test
    func testCompareAnyOrdersNaNAfterNonNaNValues() {
        let nan = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: Double.nan.bitPattern)))
        let finite = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 4.0.bitPattern)))

        #expect(kk_compare_any(nan, finite) == 1)
        #expect(kk_compare_any(finite, nan) == -1)
        #expect(kk_compare_any(nan, nan) == 0)
    }

    @Test
    func testDoubleFormattingUsesShortestScientificRepresentation() {
        #expect(runtimeFormatFloatingPoint(1e-4) == "1.0E-4")
        #expect(runtimeFormatFloatingPoint(1e7) == "1.0E7")
        #expect(runtimeFormatFloatingPoint(1.23456789e8) == "1.23456789E8")
        #expect(runtimeFormatFloatingPoint(1.0000000000000002e20) == "1.0000000000000002E20")
    }




    // MARK: - kk_array_new

    @Test
    func testArrayNewCreatesArray() {
        let array = kk_array_new(5)
        #expect(array != 0)
    }

    @Test
    func testArrayNewZeroLengthCreatesEmptyArray() {
        let array = kk_array_new(0)
        #expect(array != 0)
    }

    @Test
    func testArrayOfNullsCreatesNullableSlots() {
        var thrown = 0
        let array = kk_array_of_nulls(3, &thrown)
        #expect(thrown == 0)
        #expect(array != 0)
        #expect(kk_array_size(array) == 3)

        #expect(kk_array_get(array, 0, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
        #expect(kk_array_get(array, 1, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
        #expect(kk_array_get(array, 2, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
    }

    @Test
    func testArrayOfNullsNegativeSizeThrowsNegativeArraySizeException() throws {
        var thrown = 0
        let array = kk_array_of_nulls(-1, &thrown)

        #expect(array == 0)
        #expect(thrown != 0)
        let ptr = try #require(
            UnsafeMutableRawPointer(bitPattern: thrown),
            "negative arrayOfNulls must return a throwable"
        )
        let box = try #require(
            tryCast(ptr, to: RuntimeThrowableBox.self),
            "negative arrayOfNulls must return a RuntimeThrowableBox"
        )
        #expect(
            box.exceptionHierarchyFQNames.contains("kotlin.NegativeArraySizeException"),
            "negative arrayOfNulls must throw NegativeArraySizeException"
        )
    }

    // MARK: - kk_array_get / kk_array_set

    @Test
    func testArraySetAndGetMultipleIndices() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = kk_array_set(array, 0, 10, &thrown)
        #expect(thrown == 0)
        _ = kk_array_set(array, 1, 20, &thrown)
        #expect(thrown == 0)
        _ = kk_array_set(array, 2, 30, &thrown)
        #expect(thrown == 0)

        #expect(kk_array_get(array, 0, &thrown) == 10)
        #expect(kk_array_get(array, 1, &thrown) == 20)
        #expect(kk_array_get(array, 2, &thrown) == 30)
    }

    @Test
    func testArrayGetOutOfBoundsNegativeIndex() {
        let array = kk_array_new(2)
        var thrown = 0
        _ = kk_array_get(array, -1, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testArraySetOutOfBoundsThrows() {
        let array = kk_array_new(2)
        var thrown = 0
        _ = kk_array_set(array, 5, 99, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testArrayGetNullArrayThrows() {
        var thrown = 0
        _ = kk_array_get(0, 0, &thrown)
        #expect(thrown != 0)
    }

    @Test
    func testArraySetNullArrayThrows() {
        var thrown = 0
        _ = kk_array_set(0, 0, 42, &thrown)
        #expect(thrown != 0)
    }

    // MARK: - kk_vararg_spread_concat

    @Test
    func testVarargSpreadConcatSingleElements() {
        // pairs: [0, 10, 0, 20] means two scalar elements (marker=0)
        let pairs = kk_array_new(4)
        var thrown = 0
        _ = kk_array_set(pairs, 0, 0, &thrown) // marker: scalar
        _ = kk_array_set(pairs, 1, 10, &thrown) // value: 10
        _ = kk_array_set(pairs, 2, 0, &thrown) // marker: scalar
        _ = kk_array_set(pairs, 3, 20, &thrown) // value: 20

        let result = kk_vararg_spread_concat(pairs, 2)
        #expect(result != 0)

        #expect(kk_array_get(result, 0, &thrown) == 10)
        #expect(kk_array_get(result, 1, &thrown) == 20)
    }

    @Test
    func testVarargSpreadConcatWithSpread() {
        // Create an inner array [100, 200]
        let inner = kk_array_new(2)
        var thrown = 0
        _ = kk_array_set(inner, 0, 100, &thrown)
        _ = kk_array_set(inner, 1, 200, &thrown)

        // pairs: [-1, innerRef, 0, 300] means spread + scalar
        let pairs = kk_array_new(4)
        _ = kk_array_set(pairs, 0, -1, &thrown) // marker: spread
        _ = kk_array_set(pairs, 1, inner, &thrown) // value: array ref
        _ = kk_array_set(pairs, 2, 0, &thrown) // marker: scalar
        _ = kk_array_set(pairs, 3, 300, &thrown) // value: 300

        let result = kk_vararg_spread_concat(pairs, 2)
        #expect(kk_array_get(result, 0, &thrown) == 100)
        #expect(kk_array_get(result, 1, &thrown) == 200)
        #expect(kk_array_get(result, 2, &thrown) == 300)
    }

    @Test
    func testVarargSpreadConcatEmptyPairsReturnsEmptyArray() {
        let result = kk_vararg_spread_concat(0, 0)
        // pairCount is 0, should return empty array
        #expect(result != 0)
    }

    // MARK: - kk_println_any with boxed values

    @Test
    func testPrintlnBoxedInt() {
        let boxed = kk_box_int(42)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        #expect(output == "42")
    }

    @Test
    func testPrintlnBoxedBoolTrue() {
        let boxed = kk_box_bool(1)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        #expect(output == "true")
    }

    @Test
    func testPrintlnBoxedBoolFalse() {
        let boxed = kk_box_bool(0)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        #expect(output == "false")
    }

    @Test
    func testPrintlnBoxedString() {
        let str = makeRuntimeString("hello world")
        let output = capturePrintln { kk_println_any(str) }
        #expect(output == "hello world")
    }

    @Test
    func testPrintlnThrowable() {
        let msg = makeRuntimeString("some error")
        let throwable = __kk_throwable_new(msg)
        let output = capturePrintln { kk_println_any(throwable) }
        #expect(output.contains("some error"))
    }

    // MARK: - kk_array_fill (KUU-554)

    @Test
    func testArrayFillWritesEveryElement() {
        let array = kk_array_new(4)
        var thrown = 0
        _ = kk_array_set(array, 0, 1, &thrown)
        _ = kk_array_fill(array, 7)
        for index in 0 ..< 4 {
            #expect(kk_array_get(array, index, &thrown) == 7)
            #expect(thrown == 0)
        }
    }

    @Test
    func testArrayFillPreservesAnyFallbackTags() {
        // fill must behave like repeated kk_array_set: overwrite the payload
        // while keeping each slot's anyFallbackTag for Any-erased dispatch.
        let array = kk_array_new(3)
        _ = kk_array_set_typed(array, 0, 10, 8)
        _ = kk_array_set_typed(array, 1, 20, 5)
        _ = kk_array_set_typed(array, 2, 30, 7)
        _ = kk_array_fill(array, 0)
        let box = runtimeArrayBox(from: array)
        #expect(box?.values.map(\.anyFallbackTag) == [8, 5, 7])
        #expect(box?.values.map(\.legacyRawValue) == [0, 0, 0])
    }

    @Test
    func testArrayFillLargeArray() {
        // Exercises the O(n) subscript path; the previous elements[i] loop was
        // O(n²) and could not complete at this size.
        let array = kk_array_new(100_000)
        _ = kk_array_fill(array, 42)
        var thrown = 0
        #expect(kk_array_get(array, 0, &thrown) == 42)
        #expect(kk_array_get(array, 99_999, &thrown) == 42)
        #expect(thrown == 0)
    }

    @Test
    func testArrayCopyOfPreservesAnyFallbackTags() {
        let array = kk_array_new(2)
        _ = kk_array_set_typed(array, 0, 10, 8)
        _ = kk_array_set_typed(array, 1, 20, 6)
        let copy = __kk_array_copyOf(array)
        let box = runtimeArrayBox(from: copy)
        #expect(box?.values.map(\.anyFallbackTag) == [8, 6])
        #expect(box?.values.map(\.legacyRawValue) == [10, 20])
    }

    // MARK: - STDLIB-TEXT-FN-115: String.withIndex()


    func makeRuntimeString(_ value: String) -> UnsafeMutableRawPointer {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                kk_string_from_utf8(ptr, Int32(value.utf8.count))
            }
        }
    }

    func rawFromRuntimeString(_ value: String) -> Int {
        Int(bitPattern: makeRuntimeString(value))
    }

    func kk_println_any(_ value: Int) {
        __kk_print_raw(rawFromRuntimeString(runtimeRenderAnyForPrint(value) + "\n"))
    }

    func kk_println_any(_ value: UnsafeMutableRawPointer?) {
        kk_println_any(Int(bitPattern: value))
    }

    func makeRuntimeArray(_ values: [Int]) -> Int {
        let array = kk_array_new(values.count)
        var thrown = 0
        for (index, value) in values.enumerated() {
            _ = kk_array_set(array, index, value, &thrown)
            #expect(thrown == 0)
        }
        return array
    }

    func makeRuntimeValueArray(_ values: [RuntimeValue]) -> Int {
        let array = kk_array_new(values.count)
        guard let box = runtimeArrayBox(from: array) else {
            Issue.record("Expected RuntimeArrayBox")
            return array
        }
        box.values = values
        return array
    }

    func runtimeStringAggregateValue(_ value: String) -> RuntimeValue {
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
}
#endif
