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
private typealias RuntimeFlatStringReturnEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
private typealias RuntimeFlatStringReturnWithIntEntry = (
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
private typealias RuntimeFlatStringReturnWithIntCharEntry = (
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
private typealias RuntimeFlatStringReturnWithThreeIntsEntry = (
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
private typealias RuntimeFlatStringReturnWithTwoIntsEntry = (
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
private typealias RuntimeFlatStringReturnWithTwoStringsBoolEntry = (
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
private typealias RuntimeFlatStringReturnWithLeadingIntAndIntEntry = (
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

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private let runtimeFlatStringLengthTransform: RuntimeStringUnaryEntry = { _, strRaw, _ in
    runtimeStringFromRawOrPanic(strRaw, caller: "runtimeFlatStringLengthTransform").count
}

private let runtimeReturnValueTransform: RuntimeStringUnaryEntry = { _, valueRaw, _ in
    valueRaw
}

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeStringArrayTests {
    private func capturePrintln(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDOUT_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDOUT_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func captureStandardError(_ block: () -> Void) -> String {
        let pipe = Pipe()
        let savedFD = dup(STDERR_FILENO)
        fflush(nil)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
        block()
        fflush(nil)
        dup2(savedFD, STDERR_FILENO)
        close(savedFD)
        pipe.fileHandleForWriting.closeFile()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func withFlatString<T>(
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
                let resultData = kk_string_concat_flat(
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

    private func flatStringAsIterable(_ value: String) -> Int {
        withFlatString(value) { data, length, byteCount, hash in
            kk_string_asIterable_flat(data, length, byteCount, hash)
        }
    }

    private func makeLocale(language: String, country: String) -> Int {
        withFlatString(language) { languageData, languageLength, languageByteCount, languageHash in
            withFlatString(country) { countryData, countryLength, countryByteCount, countryHash in
                kk_locale_new_language_country_flat(
                    languageData,
                    languageLength,
                    languageByteCount,
                    languageHash,
                    countryData,
                    countryLength,
                    countryByteCount,
                    countryHash
                )
            }
        }
    }

    private func flatStringValue(
        data: UnsafePointer<UInt8>?,
        length: Int,
        byteCount: Int,
        hash: Int
    ) -> String {
        runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    }

    private func flatStringReturnValue(
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

    private func flatStringReturnValue(
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

    private func flatStringReturnValueNoThrow(
        _ value: String,
        intArg: Int,
        using call: RuntimeFlatStringReturnWithIntNoThrowEntry
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = call(data, length, byteCount, hash, intArg, &outLength, &outByteCount, &outHash)
            return flatStringValue(
                data: outData.map { UnsafePointer($0) },
                length: outLength,
                byteCount: outByteCount,
                hash: outHash
            )
        }
    }

    private func flatStringReturnValue(
        _ value: String,
        leadingIntArg: Int,
        trailingIntArg: Int,
        using call: RuntimeFlatStringReturnWithLeadingIntAndIntEntry
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

    private func flatStringReturnValue(
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

    private func flatStringReturnValue(
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

    private func flatStringReturnValue(
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

    private func flatStringReturnValue(
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

    private func doubleFromRuntimeBits(_ raw: Int) -> Double {
        Double(bitPattern: UInt64(bitPattern: Int64(raw)))
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

    // MARK: - kk_string_concat_flat

    @Test
    func testStringConcatFlatTwoStrings() {
        #expect(concatFlatValue("Hello, ", "World!") == "Hello, World!")
    }

    @Test
    func testStringConcatFlatWithNilDataLeftReturnsRightOnly() {
        #expect(concatFlatValue(nil, "World") == "World")
    }

    @Test
    func testStringConcatFlatWithNilDataRightReturnsLeftOnly() {
        #expect(concatFlatValue("Hello", nil) == "Hello")
    }

    @Test
    func testStringConcatFlatBothNilDataReturnsEmptyString() {
        #expect(concatFlatValue(nil, nil) == "")
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
    func testFloatFormattingUsesKotlinSpecialValueSpellings() {
        #expect(runtimeFormatFloatingPoint(Float.nan) == "NaN")
        #expect(runtimeFormatFloatingPoint(Float.infinity) == "Infinity")
        #expect(runtimeFormatFloatingPoint(-Float.infinity) == "-Infinity")
    }

    @Test
    func testDoubleFormattingUsesShortestScientificRepresentation() {
        #expect(runtimeFormatFloatingPoint(1e-4) == "1.0E-4")
        #expect(runtimeFormatFloatingPoint(1e7) == "1.0E7")
        #expect(runtimeFormatFloatingPoint(1.23456789e8) == "1.23456789E8")
        #expect(runtimeFormatFloatingPoint(1.0000000000000002e20) == "1.0000000000000002E20")
    }

    // MARK: - STDLIB-006 string runtime ABI

    @Test
    func testFlatStringTrimRemovesLeadingAndTrailingWhitespace() {
        #expect(flatStringReturnValue("  hello  ", using: kk_string_trim_flat) == "hello")
    }

    @Test
    func testFlatStringTrimReturnsFlattenedStringFields() {
        withFlatString("  hello  ") { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = kk_string_trim_flat(data, length, byteCount, hash, &outLength, &outByteCount, &outHash)
            #expect(flatStringValue(
                    data: outData.map { UnsafePointer($0) },
                    length: outLength,
                    byteCount: outByteCount,
                    hash: outHash
                ) == "hello")
        }
        #expect(flatStringReturnValue("KSwiftK", using: kk_string_lowercase_flat) == "kswiftk")
        #expect(flatStringReturnValue("KSwiftK", using: kk_string_uppercase_flat) == "KSWIFTK")
        #expect(flatStringReturnValue("abc", using: kk_string_reversed_flat) == "cba")
    }

    @Test
    func testFlatStringTrimStartAndTrimEndReturnFlattenedStringFields() {
        withFlatString("  hello  ") { data, length, byteCount, hash in
            var startLength = 0
            var startByteCount = 0
            var startHash = 0
            let startData = kk_string_trimStart_flat(
                data,
                length,
                byteCount,
                hash,
                &startLength,
                &startByteCount,
                &startHash
            )
            #expect(flatStringValue(
                    data: startData.map { UnsafePointer($0) },
                    length: startLength,
                    byteCount: startByteCount,
                    hash: startHash
                ) == "hello  ")

            var endLength = 0
            var endByteCount = 0
            var endHash = 0
            let endData = kk_string_trimEnd_flat(
                data,
                length,
                byteCount,
                hash,
                &endLength,
                &endByteCount,
                &endHash
            )
            #expect(flatStringValue(
                    data: endData.map { UnsafePointer($0) },
                    length: endLength,
                    byteCount: endByteCount,
                    hash: endHash
                ) == "  hello")
        }
    }

    @Test
    func testFlatStringScalarRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("KSwiftK") { data, length, byteCount, hash in
            withFlatString("swift") { needleData, needleLength, needleByteCount, needleHash in
                #expect(kk_string_compareTo_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        needleData,
                        needleLength,
                        needleByteCount,
                        needleHash
                    ) < 0)
            }
            #expect(kk_unbox_bool(kk_string_isNotEmpty_flat(data, length, byteCount, hash)) == 1)
        }
        withFlatString("  \n\t") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_isBlank_flat(data, length, byteCount, hash)) == 1)
            #expect(kk_unbox_bool(kk_string_isNotBlank_flat(data, length, byteCount, hash)) == 0)
        }
        withFlatString("") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_isNotEmpty_flat(data, length, byteCount, hash)) == 0)
        }
    }

    @Test
    func testFlatStringNullableScalarRuntimeAPIsUseDataNull() {
        #expect(kk_unbox_bool(kk_string_isNullOrEmpty_flat(nil, 0, 0, 0)) == 1)
        #expect(kk_unbox_bool(kk_string_isNullOrBlank_flat(nil, 0, 0, 0)) == 1)
        #expect(kk_unbox_bool(kk_string_equals_flat(nil, 0, 0, 0, nil, 0, 0, 0)) == 1)

        withFlatString("") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_isNullOrEmpty_flat(data, length, byteCount, hash)) == 1)
            #expect(kk_unbox_bool(kk_string_equals_flat(data, length, byteCount, hash, nil, 0, 0, 0)) == 0)
        }

        withFlatString("  \n\t") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_isNullOrBlank_flat(data, length, byteCount, hash)) == 1)
        }

        withFlatString("KSwiftK") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_isNullOrBlank_flat(data, length, byteCount, hash)) == 0)
            #expect(kk_unbox_bool(kk_string_equals_flat(data, length, byteCount, hash, nil, 0, 0, 0)) == 0)
            withFlatString("kswiftk") { otherData, otherLength, otherByteCount, otherHash in
                #expect(kk_unbox_bool(
                        kk_string_equals_flat(
                            data,
                            length,
                            byteCount,
                            hash,
                            otherData,
                            otherLength,
                            otherByteCount,
                            otherHash
                        )
                    ) == 0)
            }
            withFlatString("KSwiftK") { sameData, sameLength, sameByteCount, sameHash in
                #expect(kk_unbox_bool(
                        kk_string_equals_flat(
                            data,
                            length,
                            byteCount,
                            hash,
                            sameData,
                            sameLength,
                            sameByteCount,
                            sameHash
                        )
                    ) == 1)
            }
        }
    }

    @Test
    func testFlatStringBooleanRuntimeAPIsReturnRawScalars() {
        #expect(kk_string_isNullOrEmpty_flat(nil, 0, 0, 0) == 1)
        #expect(kk_string_isNullOrBlank_flat(nil, 0, 0, 0) == 1)
        #expect(kk_string_toBoolean_flat(nil, 0, 0, 0) == 0)

        withFlatString("KSwiftK") { data, length, byteCount, hash in
            #expect(kk_string_isEmpty_flat(data, length, byteCount, hash) == 0)
            #expect(kk_string_isNotEmpty_flat(data, length, byteCount, hash) == 1)
            #expect(kk_string_isBlank_flat(data, length, byteCount, hash) == 0)
            #expect(kk_string_isNotBlank_flat(data, length, byteCount, hash) == 1)
            #expect(kk_string_isNullOrEmpty_flat(data, length, byteCount, hash) == 0)
            #expect(kk_string_isNullOrBlank_flat(data, length, byteCount, hash) == 0)

            withFlatString("kswiftk") { otherData, otherLength, otherByteCount, otherHash in
                #expect(kk_string_equals_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        otherData,
                        otherLength,
                        otherByteCount,
                        otherHash
                    ) == 0)
            }
        }

        withFlatString("true") { data, length, byteCount, hash in
            #expect(kk_string_toBoolean_flat(data, length, byteCount, hash) == 1)
            #expect(kk_string_toBooleanStrict_flat(data, length, byteCount, hash, nil) == 1)
        }

        withFlatString("false") { data, length, byteCount, hash in
            #expect(kk_string_toBooleanStrict_flat(data, length, byteCount, hash, nil) == 0)
        }
    }

    @Test
    func testFlatStringOrEmptyUsesDataNull() {
        var nullLength = -1
        var nullByteCount = -1
        var nullHash = -1
        let nullData = kk_string_orEmpty_flat(nil, 0, 0, 0, &nullLength, &nullByteCount, &nullHash)
        #expect(nullData != nil)
        #expect(flatStringValue(
                data: nullData.map { UnsafePointer($0) },
                length: nullLength,
                byteCount: nullByteCount,
                hash: nullHash
            ) == "")
        #expect(nullLength == 0)
        #expect(nullByteCount == 0)

        #expect(flatStringReturnValue("hi", using: kk_string_orEmpty_flat) == "hi")
    }

    @Test
    func testFlatStringParseScalarRuntimeAPIsUseFlattenedStringFields() {
        #expect(kk_unbox_bool(kk_string_toBoolean_flat(nil, 0, 0, 0)) == 0)

        withFlatString("true") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(kk_string_toBoolean_flat(data, length, byteCount, hash)) == 1)
            #expect(kk_unbox_bool(kk_string_toBooleanStrict_flat(data, length, byteCount, hash, nil)) == 1)
            #expect(kk_string_toBooleanStrictOrNull_flat(data, length, byteCount, hash) == 1)
        }

        withFlatString("42") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_toInt_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(kk_string_toLong_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(kk_string_toShort_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(kk_string_toByte_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(kk_string_toIntOrNull_flat(data, length, byteCount, hash) == 42)
            #expect(kk_string_toLongOrNull_flat(data, length, byteCount, hash) == 42)
            #expect(kk_string_toShortOrNull_flat(data, length, byteCount, hash) == 42)
            #expect(kk_string_toByteOrNull_flat(data, length, byteCount, hash) == 42)
        }

        withFlatString("ff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_toInt_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
            #expect(kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
            #expect(kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
            #expect(kk_string_toByte_radix_flat(data, length, byteCount, hash, 16, &thrown) == 0)
            #expect(thrown != 0)
        }

        withFlatString("ffff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt16.max))
            #expect(thrown == 0)
        }

        withFlatString("ffffffff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt32.max))
            #expect(thrown == 0)
        }

        withFlatString("ffffffffffffffff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
            #expect(thrown == 0)
        }

        withFlatString("  -Infinity ") { data, length, byteCount, hash in
            var thrown = 0
            let doubleRaw = __kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
            #expect(thrown == 0)
            #expect(Double(bitPattern: UInt64(bitPattern: Int64(doubleRaw))) == -.infinity)

            let floatRaw = __kk_string_toFloat_flat(data, length, byteCount, hash, &thrown)
            #expect(thrown == 0)
            #expect(Float(bitPattern: UInt32(truncatingIfNeeded: UInt(bitPattern: floatRaw))) == -.infinity)
        }

        withFlatString("3.5") { data, length, byteCount, hash in
            #expect(__kk_string_toDoubleOrNull_flat(data, length, byteCount, hash) != runtimeNullSentinelInt)
            #expect(__kk_string_toFloatOrNull_flat(data, length, byteCount, hash) != runtimeNullSentinelInt)
        }

        withFlatString("nope") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_toInt_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            #expect(thrownOutput.contains("NumberFormatException"))
            #expect(kk_string_toIntOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(__kk_string_toDoubleOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(__kk_string_toFloatOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
        }
    }

    @Test
    func testFlatStringCharSelectionRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("abc") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_first_flat(data, length, byteCount, hash, &thrown) == 97)
            #expect(thrown == 0)
            #expect(kk_string_last_flat(data, length, byteCount, hash, &thrown) == 99)
            #expect(thrown == 0)
            #expect(kk_string_firstOrNull_flat(data, length, byteCount, hash) == 97)
            #expect(kk_string_lastOrNull_flat(data, length, byteCount, hash) == 99)
            #expect(kk_string_get_flat(data, length, byteCount, hash, 1, &thrown) == 98)
            #expect(thrown == 0)
            #expect(kk_string_getOrNull_flat(data, length, byteCount, hash, 1) == 98)
            #expect(kk_string_getOrNull_flat(data, length, byteCount, hash, -1) == runtimeNullSentinelInt)
            #expect(kk_string_getOrNull_flat(data, length, byteCount, hash, 3) == runtimeNullSentinelInt)

            thrown = 0
            #expect(kk_string_get_flat(data, length, byteCount, hash, 3, &thrown) == 0)
            #expect(thrown != 0)

            thrown = 0
            #expect(kk_string_single_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            #expect(thrownOutput.contains("more than one element"))
            #expect(kk_string_singleOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
        }

        withFlatString("x") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_single_flat(data, length, byteCount, hash, &thrown) == 120)
            #expect(thrown == 0)
            #expect(kk_string_singleOrNull_flat(data, length, byteCount, hash) == 120)
        }

        withFlatString("") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_string_first_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            thrown = 0
            #expect(kk_string_last_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            thrown = 0
            #expect(kk_string_single_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            #expect(kk_string_firstOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(kk_string_lastOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(kk_string_singleOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
        }
    }

    // KSP-408: indexOfFirst/indexOfLast are bundled Kotlin source (StringIndexOf.kt).
    // KSP-410: count/any/all/none/find/findLast are bundled Kotlin source
    // (StringHOF.kt). None of these lower to a flat runtime cdecl anymore;
    // coverage now lives in Scripts/diff_cases/string_hof*.kt / string_find.kt /
    // string_indexoffirst_indexoflast.kt via diff_kotlinc.sh.

    @Test
    func testStringSplitProducesListOfStrings() {
        var splitRaw = 0
        withFlatString("1,2,3") { data, length, byteCount, hash in
            withFlatString(",") { delimiterData, delimiterLength, delimiterByteCount, delimiterHash in
                splitRaw = kk_string_split_flat(
                    data,
                    length,
                    byteCount,
                    hash,
                    delimiterData,
                    delimiterLength,
                    delimiterByteCount,
                    delimiterHash
                )
            }
        }
        let list = runtimeListBox(from: splitRaw)
        #expect(list?.elements.count == 3)
        #expect(list?.elements.map(runtimeStringValue) == ["1", "2", "3"])
    }



    @Test
    func testStringToListAndToCharArrayReturnCharElements() {
        withFlatString("abc") { data, length, byteCount, hash in
            let listRaw = kk_string_toList_flat(data, length, byteCount, hash)
            let charArrayRaw = kk_string_toCharArray_flat(data, length, byteCount, hash)

            let list = runtimeListBox(from: listRaw)
            let charArray = runtimeArrayBox(from: charArrayRaw)
            #expect(list != nil)
            #expect(charArray != nil)
            let expected = [97, 98, 99]
            #expect(list?.elements.map(kk_unbox_char) == expected)
            #expect(charArray?.values.map(\.tag) == [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            #expect(charArray?.values.map(\.payload0) == expected)
            #expect(charArray?.elements == expected)
            #expect(charArray?.elements.map(kk_unbox_char) == expected)
        }
    }

    @Test
    func testStringToCharArrayStoresTaggedUTF16CodeUnits() {
        withFlatString("hi") { data, length, byteCount, hash in
            let charArrayRaw = kk_string_toCharArray_flat(data, length, byteCount, hash)
            let charArray = runtimeArrayBox(from: charArrayRaw)

            #expect(charArray?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(charArray?.values.map(\.payload0) == [104, 105])
            #expect(charArray?.elements == [104, 105])
        }
    }

    // MARK: - STDLIB-TEXT-FN-109: String.toTypedArray()

    @Test
    func testStringToTypedArrayStoresTaggedGenericCharArray() {
        withFlatString("abc") { data, length, byteCount, hash in
            let arrayRaw = kk_string_toTypedArray_flat(data, length, byteCount, hash)
            let array = runtimeArrayBox(from: arrayRaw)
            #expect(array != nil, "toTypedArray should return a RuntimeArrayBox")
            let expected = [97, 98, 99] // 'a', 'b', 'c'
            #expect(array?.values.map(\.tag) == [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            #expect(array?.elements.count == 3)
            #expect(array?.elements.map(kk_unbox_char) == expected)
        }
    }

    @Test
    func testStringCharContainersStoreTaggedRuntimeValues() {
        withFlatString("ab") { data, length, byteCount, hash in
            let listRaw = kk_string_toList_flat(data, length, byteCount, hash)
            let charArrayRaw = kk_string_toCharArray_flat(data, length, byteCount, hash)
            let typedArrayRaw = kk_string_toTypedArray_flat(data, length, byteCount, hash)
            let typedArrayListRaw = kk_array_toList(typedArrayRaw)

            let list = runtimeListBox(from: listRaw)
            let charArray = runtimeArrayBox(from: charArrayRaw)
            let typedArray = runtimeArrayBox(from: typedArrayRaw)
            let typedArrayList = runtimeListBox(from: typedArrayListRaw)

            #expect(list?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(charArray?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(typedArray?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(typedArrayList?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
            #expect(list?.elements == [97, 98])
            #expect(charArray?.elements == [97, 98])
            #expect(typedArray?.elements == [97, 98])
            #expect(runtimeRenderAnyForPrint(listRaw) == "[a, b]")
            #expect(runtimeRenderAnyForPrint(charArrayRaw) == "[a, b]")
            #expect(runtimeRenderAnyForPrint(typedArrayRaw) == "[a, b]")
            #expect(runtimeRenderAnyForPrint(typedArrayListRaw) == "[a, b]")
        }
    }

    @Test
    func testStringToTypedArrayEmptyStringReturnsEmptyArray() {
        withFlatString("") { data, length, byteCount, hash in
            let arrayRaw = kk_string_toTypedArray_flat(data, length, byteCount, hash)
            let array = runtimeArrayBox(from: arrayRaw)
            #expect(array != nil, "toTypedArray on empty string should return a RuntimeArrayBox")
            #expect(array?.elements.count == 0)
        }
    }

    @Test
    func testStringToTypedArrayIsDistinctFromToCharArray() {
        withFlatString("hi") { data, length, byteCount, hash in
            let typedArrayRaw = kk_string_toTypedArray_flat(data, length, byteCount, hash)
            let charArrayRaw = kk_string_toCharArray_flat(data, length, byteCount, hash)
            // Both should decode to the same char values but are distinct array objects
            let typedArray = runtimeArrayBox(from: typedArrayRaw)
            let charArray = runtimeArrayBox(from: charArrayRaw)
            #expect(typedArray != nil)
            #expect(charArray != nil)
            let expected = [104, 105] // 'h', 'i'
            #expect(typedArray?.elements.map(kk_unbox_char) == expected)
            #expect(charArray?.elements.map(kk_unbox_char) == expected)
            #expect(typedArrayRaw != charArrayRaw, "toTypedArray and toCharArray should return distinct array handles")
        }
    }

    // MARK: - STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)

    @Test
    func testStringToCollectionAppendsCharsToMutableList() {
        let returnedRaw = withFlatString("abc") { data, length, byteCount, hash in
            let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
            let returnedRaw = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)

            #expect(returnedRaw == destRaw, "toCollection should return the destination collection")
            return returnedRaw
        }
        let list = runtimeListBox(from: returnedRaw)
        #expect(list != nil)
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        #expect(list?.values.map(\.tag) == [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(list?.elements.map(kk_unbox_char) == expected)
    }

    @Test
    func testStringToCollectionPreservesExistingElements() {
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: [kk_box_char(97)]))
        withFlatString("de") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let list = runtimeListBox(from: destRaw)
        let expected = [97, 100, 101] // 'a', 'd', 'e'
        #expect(list?.values.map(\.tag) == [
            RuntimeValue.rawTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(list?.elements.map(kk_unbox_char) == expected)
    }

    @Test
    func testStringToCollectionEmptyStringLeavesDestinationUnchanged() {
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        withFlatString("") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let list = runtimeListBox(from: destRaw)
        #expect(list != nil)
        #expect(list?.elements.count == 0)
    }

    @Test
    func testStringToCollectionWithNonASCII() {
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        withFlatString("aé🐻") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let list = runtimeListBox(from: destRaw)
        let expected = [97, 233, 0xD83D, 0xDC3B]
        #expect(list?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag, RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(list?.elements.map(kk_unbox_char) == expected)
    }

    @Test
    func testStringToCollectionFlatAppendsCharsToMutableList() {
        withFlatString("az") { data, length, byteCount, hash in
            let destRaw = registerRuntimeObject(RuntimeListBox(elements: [kk_box_char(48)]))
            let returnedRaw = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)

            #expect(returnedRaw == destRaw, "flat toCollection should return the destination collection")
            let list = runtimeListBox(from: returnedRaw)
            let expected = [48, 97, 122] // '0', 'a', 'z'
            #expect(list?.values.map(\.tag) == [
                RuntimeValue.rawTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            #expect(list?.elements.map(kk_unbox_char) == expected)
        }
    }

    @Test
    func testStringToCollectionDeduplicatesTaggedCharsInMutableSet() {
        let destRaw = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_char(97)]))
        withFlatString("aab") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let set = runtimeSetBox(from: destRaw)
        #expect(set?.values.map(\.tag) == [RuntimeValue.rawTag, RuntimeValue.charTag])
        #expect(set?.elements.map(kk_unbox_char) == [97, 98])
    }

    // MARK: - STDLIB-TEXT-FN-108: kk_string_toSortedSet_flat tests

    @Test
    func testStringToSortedSetReturnsSortedUniqueChars() {
        // "cba" should produce {a, b, c} sorted ascending
        let setRaw = withFlatString("cba") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        #expect(setBox != nil)
        #expect(setBox?.values.map(\.tag) == [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(setBox?.elements.map(kk_unbox_char) == [97, 98, 99]) // a, b, c
    }

    @Test
    func testStringToSortedSetDeduplicates() {
        // "aabba" — unique chars are 'a'(97) and 'b'(98) in ascending order
        let setRaw = withFlatString("aabba") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        #expect(setBox != nil)
        #expect(setBox?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(setBox?.elements.map(kk_unbox_char) == [97, 98]) // a, b
    }

    @Test
    func testStringToSortedSetEmptyString() {
        let setRaw = withFlatString("") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        #expect(setBox != nil)
        #expect(setBox?.elements.count == 0)
    }

    @Test
    func testStringToSortedSetSingleChar() {
        let setRaw = withFlatString("z") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        #expect(setBox != nil)
        #expect(setBox?.values.map(\.tag) == [RuntimeValue.charTag])
        #expect(setBox?.elements.map(kk_unbox_char) == [122]) // 'z'
    }

    @Test
    func testStringToSortedSetUsesUTF16CodeUnits() {
        let setRaw = withFlatString("a🐻a") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        #expect(setBox != nil)
        #expect(setBox?.values.map(\.tag) == [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(setBox?.elements.map(kk_unbox_char) == [97, 0xD83D, 0xDC3B])
    }

    @Test
    func testFlatStringMaterializationRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("abc") { data, length, byteCount, hash in
            let expected = [97, 98, 99]

            let list = runtimeListBox(from: kk_string_toList_flat(data, length, byteCount, hash))
            let charArray = runtimeArrayBox(from: kk_string_toCharArray_flat(data, length, byteCount, hash))
            let typedArray = runtimeArrayBox(from: kk_string_toTypedArray_flat(data, length, byteCount, hash))

            #expect(list?.elements.map(kk_unbox_char) == expected)
            #expect(charArray?.elements.map(kk_unbox_char) == expected)
            #expect(typedArray?.elements.map(kk_unbox_char) == expected)
        }

        withFlatString("a🐻a") { data, length, byteCount, hash in
            let expected = [97, 0xD83D, 0xDC3B, 97]
            let list = runtimeListBox(from: kk_string_toList_flat(data, length, byteCount, hash))
            let charArray = runtimeArrayBox(from: kk_string_toCharArray_flat(data, length, byteCount, hash))
            let typedArray = runtimeArrayBox(from: kk_string_toTypedArray_flat(data, length, byteCount, hash))
            let sortedSet = runtimeSetBox(from: kk_string_toSortedSet_flat(data, length, byteCount, hash))
            #expect(list?.elements.map(kk_unbox_char) == expected)
            #expect(charArray?.elements.map(kk_unbox_char) == expected)
            #expect(typedArray?.elements.map(kk_unbox_char) == expected)
            #expect(sortedSet?.elements.map(kk_unbox_char) == [97, 0xD83D, 0xDC3B])
        }

        withFlatString("ab") { data, length, byteCount, hash in
            let withIndex = runtimeListBox(from: kk_string_withIndex_flat(data, length, byteCount, hash))
            let elements = withIndex?.elements ?? []
            #expect(elements.count == 2)
            #expect(kk_pair_first(elements[0]) == 0)
            #expect(kk_unbox_char(kk_pair_second(elements[0])) == 97)
            #expect(kk_pair_first(elements[1]) == 1)
            #expect(kk_unbox_char(kk_pair_second(elements[1])) == 98)

            let iteratorRaw = kk_string_iterator_flat(data, length, byteCount, hash)
            #expect(kk_string_iterator_hasNext(iteratorRaw) == 1)
            #expect(kk_unbox_char(kk_string_iterator_next(iteratorRaw)) == 97)
            #expect(kk_string_iterator_hasNext(iteratorRaw) == 1)
            #expect(kk_unbox_char(kk_string_iterator_next(iteratorRaw)) == 98)
            #expect(kk_string_iterator_hasNext(iteratorRaw) == 0)
        }

        withFlatString("") { data, length, byteCount, hash in
            #expect(runtimeListBox(from: kk_string_toList_flat(data, length, byteCount, hash))?.elements.count == 0)
            #expect(runtimeArrayBox(from: kk_string_toCharArray_flat(data, length, byteCount, hash))?.elements.count == 0)
            #expect(runtimeArrayBox(from: kk_string_toTypedArray_flat(data, length, byteCount, hash))?.elements.count == 0)
            #expect(runtimeSetBox(from: kk_string_toSortedSet_flat(data, length, byteCount, hash))?.elements.count == 0)
            #expect(runtimeListBox(from: kk_string_withIndex_flat(data, length, byteCount, hash))?.elements.count == 0)
            #expect(kk_string_iterator_hasNext(kk_string_iterator_flat(data, length, byteCount, hash)) == 0)
        }
    }

    // MARK: - STDLIB-317: String.asIterable() tests

    @Test
    func testStringAsIterableReturnsLazyBox() {
        let iterableRaw = flatStringAsIterable("abc")

        // The iterable should be a RuntimeStringIterableBox, not a list.
        let iterableBox = runtimeStringIterableBox(from: iterableRaw)
        #expect(iterableBox != nil, "asIterable should return a RuntimeStringIterableBox")
        #expect(iterableBox?.source == "abc", "Box should store the immutable string payload")

        // It should NOT be a list (lazy, not materialised).
        let listBox = runtimeListBox(from: iterableRaw)
        #expect(listBox == nil, "asIterable should NOT materialise a list eagerly")
    }

    @Test
    func testFlatStringListSequenceRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("a,b,c") { data, length, byteCount, hash in
            withFlatString(",") { delimiterData, delimiterLength, delimiterByteCount, delimiterHash in
                let split = runtimeListBox(from: kk_string_split_flat(
                    data,
                    length,
                    byteCount,
                    hash,
                    delimiterData,
                    delimiterLength,
                    delimiterByteCount,
                    delimiterHash
                ))
                #expect(split?.elements.map(runtimeStringValue) == ["a", "b", "c"])

                let splitLimit = runtimeListBox(from: kk_string_split_limit_flat(
                    data,
                    length,
                    byteCount,
                    hash,
                    delimiterData,
                    delimiterLength,
                    delimiterByteCount,
                    delimiterHash,
                    0,
                    2
                ))
                #expect(splitLimit?.elements.map(runtimeStringValue) == ["a", "b,c"])

                let splitSequence = kk_string_splitToSequence_flat(
                    data,
                    length,
                    byteCount,
                    hash,
                    delimiterData,
                    delimiterLength,
                    delimiterByteCount,
                    delimiterHash
                )
                #expect(runtimeSequenceSourceElements(from: splitSequence)?.map(runtimeStringValue) == ["a", "b", "c"])
            }
        }

        withFlatString("aé") { data, length, byteCount, hash in
            let iterableRaw = kk_string_asIterable_flat(data, length, byteCount, hash)
            let iterableBox = runtimeStringIterableBox(from: iterableRaw)
            #expect(iterableBox?.source == "aé")
            #expect(runtimeListBox(from: iterableRaw) == nil, "asIterable should stay lazy on the flat ABI path")
            let list = runtimeListBox(from: kk_string_iterable_toList(iterableRaw))
            #expect(list?.elements.map(kk_unbox_char) == [97, 233])
        }

        withFlatString("a🐻") { data, length, byteCount, hash in
            let sequenceRaw = kk_string_asSequence_flat(data, length, byteCount, hash)
            #expect(runtimeSequenceSourceElements(from: sequenceRaw)?.map(kk_unbox_char) == [97, 0xD83D, 0xDC3B])

            let list = runtimeListBox(from: kk_sequence_to_list(sequenceRaw, nil))
            #expect(list?.values.map(\.tag) == [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            #expect(list?.elements == [97, 0xD83D, 0xDC3B])

            let mutableList = runtimeListBox(from: kk_sequence_toMutableList(sequenceRaw))
            #expect(mutableList?.values.map(\.tag) == [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            #expect(mutableList?.elements == [97, 0xD83D, 0xDC3B])
        }
    }

    @Test
    func testStringAsSequenceGenericConversionsPreserveTaggedUTF16Chars() {
        let sequenceRaw = withFlatString("aba") { data, length, byteCount, hash in
            kk_string_asSequence_flat(data, length, byteCount, hash)
        }

        let set = runtimeSetBox(from: kk_sequence_toSet(sequenceRaw))
        let mutableSet = runtimeSetBox(from: kk_sequence_toMutableSet(sequenceRaw))
        let hashSet = runtimeSetBox(from: kk_sequence_toHashSet(sequenceRaw))
        let sortedSet = runtimeSetBox(from: kk_sequence_toSortedSet(sequenceRaw))
        let destinationRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        _ = kk_sequence_toCollection(sequenceRaw, destinationRaw)
        let destination = runtimeListBox(from: destinationRaw)

        #expect(set?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(mutableSet?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(hashSet?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(sortedSet?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(destination?.values.map(\.tag) == [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(set?.elements == [97, 98])
        #expect(mutableSet?.elements == [97, 98])
        #expect(hashSet?.elements == [97, 98])
        #expect(sortedSet?.elements == [97, 98])
        #expect(destination?.elements == [97, 98, 97])
    }

    @Test
    func testFlatStringChunkedWindowedRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("abcde") { data, length, byteCount, hash in
            let chunks = runtimeListBox(from: kk_string_chunked_flat(data, length, byteCount, hash, 2))
            #expect(chunks?.elements.map(runtimeStringValue) == ["ab", "cd", "e"])

            let chunkSequence = kk_string_chunked_sequence_flat(data, length, byteCount, hash, 3)
            #expect(runtimeSequenceSourceElements(from: chunkSequence)?.map(runtimeStringValue) == ["abc", "de"])

            var thrown = -1
            let transformedChunks = kk_string_chunked_sequence_transform_flat(
                data,
                length,
                byteCount,
                hash,
                2,
                unsafeBitCast(runtimeFlatStringLengthTransform, to: Int.self),
                0,
                &thrown
            )
            #expect(thrown == 0)
            assertRawValueSequence(transformedChunks, equals: [2, 2, 1])

            thrown = -1
            let transformedChunkStrings = kk_string_chunked_sequence_transform_flat(
                data,
                length,
                byteCount,
                hash,
                2,
                unsafeBitCast(runtimeReturnValueTransform, to: Int.self),
                0,
                &thrown
            )
            #expect(thrown == 0)
            assertStringValueSequence(transformedChunkStrings, equals: ["ab", "cd", "e"])

            let defaultWindows = runtimeListBox(from: kk_string_windowed_default_flat(data, length, byteCount, hash, 3))
            #expect(defaultWindows?.elements.map(runtimeStringValue) == ["abc", "bcd", "cde"])

            let steppedWindows = runtimeListBox(from: kk_string_windowed_flat(data, length, byteCount, hash, 3, 2))
            #expect(steppedWindows?.elements.map(runtimeStringValue) == ["abc", "cde"])

            let partialWindows = runtimeListBox(from: kk_string_windowed_partial_flat(data, length, byteCount, hash, 3, 2, 1))
            #expect(partialWindows?.elements.map(runtimeStringValue) == ["abc", "cde", "e"])

            let partialWindowSequence = kk_string_windowedSequence_partial_flat(data, length, byteCount, hash, 3, 2, 1)
            #expect(runtimeSequenceSourceElements(from: partialWindowSequence)?.map(runtimeStringValue) == ["abc", "cde", "e"])

            thrown = -1
            let transformedWindows = kk_string_windowedSequence_transform_flat(
                data,
                length,
                byteCount,
                hash,
                3,
                2,
                1,
                unsafeBitCast(runtimeFlatStringLengthTransform, to: Int.self),
                0,
                &thrown
            )
            #expect(thrown == 0)
            assertRawValueSequence(transformedWindows, equals: [3, 3, 1])

            thrown = -1
            let transformedWindowStrings = kk_string_windowedSequence_transform_flat(
                data,
                length,
                byteCount,
                hash,
                3,
                2,
                1,
                unsafeBitCast(runtimeReturnValueTransform, to: Int.self),
                0,
                &thrown
            )
            #expect(thrown == 0)
            assertStringValueSequence(transformedWindowStrings, equals: ["abc", "cde", "e"])
        }

        withFlatString("") { data, length, byteCount, hash in
            #expect(runtimeListBox(from: kk_string_chunked_flat(data, length, byteCount, hash, 2))?.elements.count == 0)
            #expect(runtimeListBox(from: kk_string_windowed_default_flat(data, length, byteCount, hash, 2))?.elements.count == 0)
        }
    }

    @Test
    func testStringChunkedWindowedContainersAvoidLegacyStringBoxes() {
        withFlatString("abcde") { data, length, byteCount, hash in
            let baselineObjectCount = kk_debugging_global_object_count()

            let chunksRaw = kk_string_chunked_flat(data, length, byteCount, hash, 2)

            #expect(kk_debugging_global_object_count() == baselineObjectCount + 1, "kk_string_chunked_flat should only allocate the list container")
            let chunks = runtimeListBox(from: chunksRaw)
            #expect(chunks?.values.map(\.tag) == [
                RuntimeValue.stringTag,
                RuntimeValue.stringTag,
                RuntimeValue.stringTag,
            ])
            #expect(chunks?.values.map(runtimeFlatStringValue) == ["ab", "cd", "e"])
            #expect(kk_debugging_global_object_count() == baselineObjectCount + 1)
        }

        withFlatString("abcde") { data, length, byteCount, hash in
            let baselineObjectCount = kk_debugging_global_object_count()

            let sequenceRaw = kk_string_chunked_sequence_flat(data, length, byteCount, hash, 3)

            #expect(kk_debugging_global_object_count() == baselineObjectCount + 1, "kk_string_chunked_sequence_flat should build a direct sequence without an intermediate list")
            guard let sequence = runtimeSequenceBox(from: sequenceRaw),
                  case let .valueSource(values)? = sequence.steps.first
            else {
                Issue.record("Expected direct valueSource sequence")
                return
            }
            #expect(values.map(\.tag) == [RuntimeValue.stringTag, RuntimeValue.stringTag])
            #expect(values.map(runtimeFlatStringValue) == ["abc", "de"])
            #expect(kk_debugging_global_object_count() == baselineObjectCount + 1)
        }

        withFlatString("abcde") { data, length, byteCount, hash in
            let baselineObjectCount = kk_debugging_global_object_count()

            let windowsRaw = kk_string_windowed_partial_flat(data, length, byteCount, hash, 3, 2, 1)

            #expect(kk_debugging_global_object_count() == baselineObjectCount + 1, "kk_string_windowed_partial_flat should only allocate the list container")
            let windows = runtimeListBox(from: windowsRaw)
            #expect(windows?.values.map(\.tag) == [
                RuntimeValue.stringTag,
                RuntimeValue.stringTag,
                RuntimeValue.stringTag,
            ])
            #expect(windows?.values.map(runtimeFlatStringValue) == ["abc", "cde", "e"])
            #expect(kk_debugging_global_object_count() == baselineObjectCount + 1)
        }
    }

    @Test
    func testStringAsIterableToListMaterialises() {
        let iterableRaw = flatStringAsIterable("abc")
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        #expect(list != nil)
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        #expect(list?.elements.map(kk_unbox_char) == expected)
    }

    @Test
    func testStringAsIterableIteratorYieldsCharacters() {
        let iterableRaw = flatStringAsIterable("hi")
        let iterRaw = kk_string_iterable_iterator(iterableRaw)

        #expect(kk_string_iterator_hasNext(iterRaw) == 1)
        let first = kk_unbox_char(kk_string_iterator_next(iterRaw))
        #expect(first == 104) // 'h'

        #expect(kk_string_iterator_hasNext(iterRaw) == 1)
        let second = kk_unbox_char(kk_string_iterator_next(iterRaw))
        #expect(second == 105) // 'i'

        #expect(kk_string_iterator_hasNext(iterRaw) == 0)
    }

    @Test
    func testStringIteratorNextReturnsRawUTF16CodeUnits() {
        let iterableRaw = flatStringAsIterable("hi")
        let iterRaw = kk_string_iterable_iterator(iterableRaw)

        #expect(kk_string_iterator_next(iterRaw) == 104)
        #expect(kk_string_iterator_next(iterRaw) == 105)
        #expect(kk_string_iterator_next(iterRaw) == 0)
    }

    @Test
    func testStringAsIterableWithNonASCII() {
        let iterableRaw = flatStringAsIterable("aé🐻")
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        let expectedCodeUnits: [Int] = [97, 233, 0xD83D, 0xDC3B]
        #expect(list?.values.map(\.tag) == Array(repeating: RuntimeValue.charTag, count: expectedCodeUnits.count))
        #expect(list?.elements.map(kk_unbox_char) == expectedCodeUnits)

        let iteratorRaw = kk_string_iterable_iterator(iterableRaw)
        #expect(kk_string_iterator_next(iteratorRaw) == 97)
        #expect(kk_string_iterator_next(iteratorRaw) == 233)
        #expect(kk_string_iterator_next(iteratorRaw) == 0xD83D)
        #expect(kk_string_iterator_next(iteratorRaw) == 0xDC3B)
        #expect(kk_string_iterator_hasNext(iteratorRaw) == 0)
    }

    @Test
    func testStringAsIterableGenericConversionsPreserveTaggedChars() {
        let iterableRaw = flatStringAsIterable("aba")

        let mutableList = runtimeListBox(from: kk_collection_toMutableList(iterableRaw))
        let mutableSet = runtimeSetBox(from: kk_iterable_toMutableSet(iterableRaw))

        #expect(mutableList?.values.map(\.tag) == [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(mutableList?.elements == [97, 98, 97])
        #expect(mutableSet?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(mutableSet?.elements == [97, 98])
    }

    @Test
    func testStringCharCollectionCopiesPreserveTaggedChars() {
        let listRaw = kk_collection_toMutableList(flatStringAsIterable("aba"))

        let set = runtimeSetBox(from: kk_list_to_set(listRaw))
        let mutableSet = runtimeSetBox(from: kk_list_to_mutable_set(listRaw))
        let hashSet = runtimeSetBox(from: kk_list_toHashSet(listRaw))
        let mutableList = runtimeListBox(from: kk_collection_toMutableList(listRaw))
        let typedArray = runtimeArrayBox(from: kk_collection_toTypedArray(listRaw))

        #expect(set?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(mutableSet?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(hashSet?.values.map(\.tag) == [RuntimeValue.charTag, RuntimeValue.charTag])
        #expect(mutableList?.values.map(\.tag) == [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(typedArray?.values.map(\.tag) == [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        #expect(set?.elements == [97, 98])
        #expect(mutableList?.elements == [97, 98, 97])
        #expect(typedArray?.elements == [97, 98, 97])
    }

    @Test
    func testStringAsIterableGenericJoinToStringRendersTaggedChars() {
        let iterableRaw = flatStringAsIterable("aé🐻")
        let result = kk_iterable_joinToString(
            iterableRaw,
            rawFromRuntimeString("|"),
            rawFromRuntimeString("<"),
            rawFromRuntimeString(">")
        )

        #expect(runtimeStringValue(Int(bitPattern: result)) == "<a|é|?|?>")
    }

    @Test
    func testStringJoinToStringUsesAggregateListStorageWithoutLegacyStringBoxes() {
        let listRaw = makeRuntimeValueList([
            runtimeStringAggregateValue("red"),
            runtimeStringAggregateValue("green"),
            runtimeStringAggregateValue("blue"),
        ])
        let separatorRaw = rawFromRuntimeString("|")
        let prefixRaw = rawFromRuntimeString("<")
        let postfixRaw = rawFromRuntimeString(">")
        let baselineObjectCount = kk_debugging_global_object_count()

        let resultRaw = kk_string_joinToString(listRaw, separatorRaw, prefixRaw, postfixRaw)

        #expect(runtimeStringValue(resultRaw) == "<red|green|blue>")
        #expect(kk_debugging_global_object_count() == baselineObjectCount + 1, "kk_string_joinToString must not materialize RuntimeStringBox values from aggregate list storage")
    }

    @Test
    func testStringAsIterableEmptyString() {
        let iterableRaw = flatStringAsIterable("")
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        #expect(list != nil)
        #expect(list?.elements.count == 0)
    }

    @Test
    func testStringIterableHelpersDoNotAcceptLegacyRawStringHandles() {
        let legacyRaw = rawFromRuntimeString("abc")

        let list = runtimeListBox(from: kk_string_iterable_toList(legacyRaw))
        #expect(list?.elements.count == 0)

        let iterator = kk_string_iterable_iterator(legacyRaw)
        #expect(kk_string_iterator_hasNext(iterator) == 0)
    }

    @Test
    func testStringAsIterablePrintDoesNotMaterialiseList() {
        let iterableRaw = flatStringAsIterable("aé🐻")
        let baselineObjectCount = kk_runtime_heap_object_count()

        let output = capturePrintln {
            kk_println_any(UnsafeMutableRawPointer(bitPattern: iterableRaw))
        }

        #expect(output == "[a, é, 🐻]")
        #expect(kk_runtime_heap_object_count() == baselineObjectCount)
    }

    @Test
    func testStringAsIterableRenderDoesNotMaterialiseList() {
        let iterableRaw = flatStringAsIterable("abc")
        let baselineObjectCount = kk_runtime_heap_object_count()

        #expect(runtimeRenderAnyForPrint(iterableRaw) == "[a, b, c]")
        #expect(kk_runtime_heap_object_count() == baselineObjectCount)
    }

    @Test
    func testStringFunctionsWithNonASCII() {
        let text = "aé🐻"
        let listRaw = kk_string_toList(rawFromRuntimeString(text))
        let list = runtimeListBox(from: listRaw)
        let expectedCodeUnits: [Int] = [97, 233, 0xD83D, 0xDC3B]
        #expect(list?.elements.map(kk_unbox_char) == expectedCodeUnits)
    }

    @Test
    func testStringCodePointCountUsesUTF16Ranges() {
        let textRaw = rawFromRuntimeString("a😀b")

        #expect(__kk_string_codePointCount(textRaw) == 3)

        var thrown = 0
        #expect(__kk_string_codePointCount_from(textRaw, 1, &thrown) == 2)
        #expect(thrown == 0)

        thrown = 0
        #expect(__kk_string_codePointCount_range(textRaw, 1, 3, &thrown) == 1)
        #expect(thrown == 0)

        thrown = 0
        #expect(__kk_string_codePointCount_range(textRaw, 0, 2, &thrown) == 2)
        #expect(thrown == 0)
    }

    @Test
    func testStringCodePointCountReportsRangeErrors() {
        let textRaw = rawFromRuntimeString("abc")

        var thrown = 0
        #expect(__kk_string_codePointCount_range(textRaw, -1, 1, &thrown) == 0)
        #expect(thrown != 0)

        thrown = 0
        #expect(__kk_string_codePointCount_range(textRaw, 0, 4, &thrown) == 0)
        #expect(thrown != 0)

        thrown = 0
        #expect(__kk_string_codePointCount_range(textRaw, 2, 1, &thrown) == 0)
        #expect(thrown != 0)
    }

    @Test
    func testPairAndArrayRenderingStayDistinct() {
        let pairRaw = kk_pair_new(1, 2)
        #expect(runtimeElementToString(pairRaw) == "(1, 2)")
        #expect(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: pairRaw)) } == "(1, 2)")

        var thrown = 0
        let arrayRaw = kk_array_new(2)
        _ = kk_array_set(arrayRaw, 0, 1, &thrown)
        _ = kk_array_set(arrayRaw, 1, 2, &thrown)
        #expect(runtimeElementToString(arrayRaw) == "[1, 2]")
        #expect(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: arrayRaw)) } == "[1, 2]")
    }

    @Test
    func testThrowableStringConversionMatchesPrintln() {
        // Regression test: runtimeElementToString (used by kk_any_to_string, which
        // string template interpolation and the `+` concatenation operator lower to)
        // used to be missing a RuntimeThrowableBox case and fell through to printing
        // the raw pointer bit pattern instead of "Throwable(ExceptionName: message)".
        let throwableRaw = runtimeAllocateIllegalStateException(message: "boom")
        let expected = "Throwable(IllegalStateException: boom)"

        #expect(runtimeElementToString(throwableRaw) == expected)
        #expect(runtimeRenderAnyForPrint(throwableRaw) == expected)
        #expect(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: throwableRaw)) } == expected)

        // anyFallbackTag() emits tag 1 ("default"/object) for class-typed operands
        // of `+`/string templates, so this exercises the exact ABI path the compiler
        // lowers `"$e"` and `"foo: " + e` to.
        let converted = kk_any_to_string(throwableRaw, 1)
        #expect(extractString(from: converted) ?? "" == expected)
    }

    // KSP-405: take/drop are bundled Kotlin source (StringTakeDrop.kt);
    // their runtime bridges and direct tests were removed.

    @Test
    func testStringRepeatFlatFunction() {
        #expect(flatStringReturnValue("ab", intArg: 0, using: kk_string_repeat_flat) == "")
        #expect(flatStringReturnValue("ab", intArg: 3, using: kk_string_repeat_flat) == "ababab")
        #expect(flatStringReturnValue("é", intArg: 2, using: kk_string_repeat_flat) == "éé")
    }

    @Test
    func testStringRepeatFlatNegativeThrowsIllegalArgumentException() {
        var thrown = 0
        _ = flatStringReturnValue("hello", intArg: -1, using: kk_string_repeat_flat, outThrown: &thrown)
        #expect(thrown != 0, "kk_string_repeat_flat(-1) should set outThrown")
    }

    @Test
    func testStringReplaceSupportsLiteralReplacement() {
        withFlatString("aba") { data, length, byteCount, hash in
            withFlatString("a") { oldData, oldLength, oldByteCount, oldHash in
                withFlatString("z") { newData, newLength, newByteCount, newHash in
                    var outLength = 0
                    var outByteCount = 0
                    var outHash = 0
                    let result = kk_string_replace_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        oldData,
                        oldLength,
                        oldByteCount,
                        oldHash,
                        newData,
                        newLength,
                        newByteCount,
                        newHash,
                        &outLength,
                        &outByteCount,
                        &outHash
                    )
                    #expect(flatStringValue(
                            data: result.map { UnsafePointer($0) },
                            length: outLength,
                            byteCount: outByteCount,
                            hash: outHash
                        ) == "zbz")
                }
            }
        }
    }

    // MARK: - STDLIB-TEXT-FN-055: replace overloads

    @Test
    func testStringReplaceCharReplacesAllOccurrences() {
        let replaced = flatStringReturnValue(
            "hello world",
            intArg: kk_box_char(Int("l".unicodeScalars.first!.value)),
            charArg: kk_box_char(Int("r".unicodeScalars.first!.value)),
            using: kk_string_replace_char_flat
        )
        #expect(replaced == "herro worrd")
    }

    @Test
    func testStringReplaceCharHandlesNoMatch() {
        let replaced = flatStringReturnValue(
            "hello",
            intArg: kk_box_char(Int("z".unicodeScalars.first!.value)),
            charArg: kk_box_char(Int("x".unicodeScalars.first!.value)),
            using: kk_string_replace_char_flat
        )
        #expect(replaced == "hello")
    }

    @Test
    func testStringReplaceIgnoreCaseCaseSensitiveMatch() {
        let replaced = flatStringReturnValue(
            "Hello World",
            first: "hello",
            second: "Hi",
            ignoreCase: true,
            using: kk_string_replace_ignoreCase_flat
        )
        #expect(replaced == "Hi World")
    }

    @Test
    func testStringReplaceIgnoreCaseCaseSensitiveFalse() {
        let replaced = flatStringReturnValue(
            "Hello World",
            first: "hello",
            second: "Hi",
            ignoreCase: false,
            using: kk_string_replace_ignoreCase_flat
        )
        #expect(replaced == "Hello World")
    }

    @Test
    func testStringReplaceCharIgnoreCaseReplaces() {
        let replaced = flatStringReturnValue(
            "Hello World",
            firstIntArg: kk_box_char(Int("h".unicodeScalars.first!.value)),
            secondIntArg: kk_box_char(Int("J".unicodeScalars.first!.value)),
            thirdIntArg: 1,
            using: kk_string_replace_char_ignoreCase_flat
        )
        #expect(replaced == "Jello World")
    }

    @Test
    func testStringReplaceCharIgnoreCaseFalseIsCaseSensitive() {
        let replaced = flatStringReturnValue(
            "Hello World",
            firstIntArg: kk_box_char(Int("h".unicodeScalars.first!.value)),
            secondIntArg: kk_box_char(Int("J".unicodeScalars.first!.value)),
            thirdIntArg: 0,
            using: kk_string_replace_char_ignoreCase_flat
        )
        #expect(replaced == "Hello World")
    }

    @Test
    func testStringToIntSuccessAndFailure() {
        var thrown = 0
        withFlatString("42") { data, length, byteCount, hash in
            let value = kk_string_toInt_flat(data, length, byteCount, hash, &thrown)
            #expect(thrown == 0)
            #expect(value == 42)
        }

        withFlatString("4x") { data, length, byteCount, hash in
            _ = kk_string_toInt_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("NumberFormatException"))
    }

    @Test
    func testStringToIntRadixThrowsOnInvalidRadix() {
        var thrown = 0

        withFlatString("10") { data, length, byteCount, hash in
            _ = kk_string_toInt_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("IllegalArgumentException"))
    }

    @Test
    func testStringToIntOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ff") { data, length, byteCount, hash in
            #expect(kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        #expect(result == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("IllegalArgumentException"))
    }

    @Test
    func testStringToUByteOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ff") { data, length, byteCount, hash in
            #expect(kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
        }
        withFlatString("100") { data, length, byteCount, hash in
            #expect(kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToUByteOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        #expect(result == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("IllegalArgumentException"))
    }

    @Test
    func testStringToUShortOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ffff") { data, length, byteCount, hash in
            #expect(kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt16.max))
            #expect(thrown == 0)
        }
        withFlatString("10000") { data, length, byteCount, hash in
            #expect(kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToUShortOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        #expect(result == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("IllegalArgumentException"))
    }

    @Test
    func testStringToUIntOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ffffffff") { data, length, byteCount, hash in
            #expect(kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt32.max))
            #expect(thrown == 0)
        }
        withFlatString("100000000") { data, length, byteCount, hash in
            #expect(kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToUIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        #expect(result == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("IllegalArgumentException"))
    }

    @Test
    func testStringToULongOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ffffffffffffffff") { data, length, byteCount, hash in
            #expect(kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
            #expect(thrown == 0)
        }
        withFlatString("10000000000000000") { data, length, byteCount, hash in
            #expect(kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToULongOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        #expect(result == runtimeNullSentinelInt)
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("IllegalArgumentException"))
    }

    @Test
    func testStringToDoubleParsesSpecialValuesAndThrowsOnInvalidInput() {
        var thrown = 0
        let parsed = withFlatString("  -Infinity ") { data, length, byteCount, hash in
            __kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(doubleFromRuntimeBits(parsed) == -.infinity)

        let nanRaw = withFlatString("NaN") { data, length, byteCount, hash in
            __kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown == 0)
        #expect(doubleFromRuntimeBits(nanRaw).isNaN)

        withFlatString("nope") { data, length, byteCount, hash in
            _ = __kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("NumberFormatException"))
    }

    @Test
    func testStringToDoubleParsesKotlinFloatingLiterals() {
        var thrown = 0
        let cases: [(String, Double)] = [
            ("1.", 1.0),
            (".5", 0.5),
            ("1e3", 1_000.0),
            ("1.0d", 1.0),
            ("+6.25F", 6.25),
            ("0x1.8p1", 3.0),
        ]

        for (source, expected) in cases {
            let raw = __kk_string_toDouble(rawFromRuntimeString(source), &thrown)
            #expect(thrown == 0, "Expected \(source) to parse")
            #expect(abs(doubleFromRuntimeBits(raw) - expected) <= 1e-12)
        }
    }

    @Test
    func testStringToDoubleRejectsSwiftOnlySpellings() {
        var thrown = 0

        _ = __kk_string_toDouble(rawFromRuntimeString("nan"), &thrown)
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("NumberFormatException"))

        let parsedInf = withFlatString("inf") { data, length, byteCount, hash in
            __kk_string_toDoubleOrNull_flat(data, length, byteCount, hash)
        }
        #expect(parsedInf == runtimeNullSentinelInt)

        let parsed = withFlatString("0x1p2D") { data, length, byteCount, hash in
            __kk_string_toDoubleOrNull_flat(data, length, byteCount, hash)
        }
        #expect(parsed != runtimeNullSentinelInt)
        #expect(abs(doubleFromRuntimeBits(parsed) - 4.0) <= 1e-12)
    }

    @Test
    func testStringFormatSupportsStringIntAndDoubleSpecifiers() {
        let args = makeRuntimeArray([
            rawFromRuntimeString("age"),
            7,
            Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern)),
        ])

        let formatted = flatStringReturnValueNoThrow("%s:%d %.2f", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "age:7 3.50")
    }

    @Test
    func testStringFormatUsesAggregateArgumentStorageWithoutLegacyStringBoxes() {
        let args = makeRuntimeValueArray([
            runtimeStringAggregateValue("age"),
            RuntimeValue(raw: 7),
            runtimeStringAggregateValue("3.5"),
        ])
        let baselineObjectCount = kk_debugging_global_object_count()

        let formatted = flatStringReturnValueNoThrow("%s:%d %.1f", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "age:7 3.5")

        let formattedWithLocale = flatStringReturnValue(
            "%1$s %3$.1f",
            leadingIntArg: runtimeNullSentinelInt,
            trailingIntArg: args,
            using: __kk_string_format_locale_flat
        )
        #expect(formattedWithLocale == "age 3.5")
        #expect(kk_debugging_global_object_count() == baselineObjectCount, "String.format must not materialize RuntimeStringBox values from aggregate argument storage")
    }

    @Test
    func testStringFormatSupportsFloatingSpecifiersForIntegersAndBoxedFloats() {
        let args = makeRuntimeArray([
            3,
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
        ])

        let formatted = flatStringReturnValueNoThrow("%.1f %.1f %.1f", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "3.0 1.5 2.5")
    }

    @Test
    func testStringFormatSupportsPositionalArguments() {
        let args = makeRuntimeArray([
            7,
            rawFromRuntimeString("age"),
        ])

        let formatted = flatStringReturnValueNoThrow("%2$s:%1$d", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "age:7")
    }

    @Test
    func testStringFormatSupportsBooleanSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_bool(1),
            kk_box_bool(0),
            runtimeNullSentinelInt,
        ])

        let formatted = flatStringReturnValueNoThrow("%b %B %b", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "true FALSE false")
    }

    @Test
    func testStringFormatPreservesSixtyFourBitIntegerWidth() {
        let signed = Int(Int64.max)
        let unsigned = Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
        let args = makeRuntimeArray([signed, unsigned])

        let formatted = flatStringReturnValueNoThrow("%d %x", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "9223372036854775807 ffffffffffffffff")
    }

    @Test
    func testStringFormatSupportsBoxedIntegerSpecifiers() {
        let boxedSigned = kk_box_long(Int(Int64.max))
        let boxedUnsigned = kk_box_long(Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
        let args = makeRuntimeArray([boxedSigned, boxedUnsigned])

        let formatted = flatStringReturnValueNoThrow("%d %x", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "9223372036854775807 ffffffffffffffff")
    }

    @Test
    func testStringFormatSupportsBoxedScalarStringSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_long(Int(Int64.max)),
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
            kk_box_char(Int(Character("A").unicodeScalars.first?.value ?? 0)),
            kk_box_bool(1),
        ])

        let formatted = flatStringReturnValueNoThrow("%s %s %s %s %s", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "9223372036854775807 1.5 2.5 A true")
    }

    @Test
    func testStringFormatSupportsEscapedPercentWithoutArguments() {
        let formatted = flatStringReturnValueNoThrow("progress=100%%", intArg: kk_array_new(0), using: __kk_string_format_flat)
        #expect(formatted == "progress=100%")
    }

    @Test
    func testStringFormatTreatsUnsupportedUnsignedConversionAsLiteral() {
        let args = makeRuntimeArray([7])
        let formatted = flatStringReturnValueNoThrow("%u", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "%u")
    }

    @Test
    func testStringFormatGroupsIntegersForGroupingFlag() {
        let args = makeRuntimeArray([1234567])
        let formatted = flatStringReturnValueNoThrow("%,d", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "1,234,567")
    }

    @Test
    func testStringFormatZeroPadsGroupedIntegersAfterGrouping() {
        let args = makeRuntimeArray([1234])
        let formatted = flatStringReturnValueNoThrow("%,012d", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "00000001,234")
    }

    @Test
    func testStringFormatSupportsScientificNotationForDouble() {
        let args = makeRuntimeArray([kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 1234.5.bitPattern)))])
        let formatted = flatStringReturnValueNoThrow("%.2e", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "1.23e+03")
    }

    @Test
    func testStringFormatLocaleUsesLocaleDecimalSeparator() {
        let locale = makeLocale(language: "de", country: "DE")
        let args = makeRuntimeArray([
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern))),
        ])
        let formatted = flatStringReturnValue(
            "%.1f",
            leadingIntArg: locale,
            trailingIntArg: args,
            using: __kk_string_format_locale_flat
        )
        #expect(formatted == "3,5")
    }

    @Test
    func testStringFormatLocaleGroupsOnlyWithGroupingFlag() {
        let locale = makeLocale(language: "de", country: "DE")
        let ungrouped = flatStringReturnValue(
            "%d",
            leadingIntArg: locale,
            trailingIntArg: makeRuntimeArray([1234567]),
            using: __kk_string_format_locale_flat
        )
        #expect(ungrouped == "1234567")

        let grouped = flatStringReturnValue(
            "%,d",
            leadingIntArg: makeLocale(language: "de", country: "DE"),
            trailingIntArg: makeRuntimeArray([1234567]),
            using: __kk_string_format_locale_flat
        )
        #expect(grouped == "1.234.567")
    }

    @Test
    func testStringFormatNullLocaleKeepsNonLocalizedFormatting() {
        let args = makeRuntimeArray([
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern))),
        ])
        let formatted = flatStringReturnValue(
            "%.1f",
            leadingIntArg: runtimeNullSentinelInt,
            trailingIntArg: args,
            using: __kk_string_format_locale_flat
        )
        #expect(formatted == "3.5")
    }

    // MARK: - __kk_throwable_new

    @Test
    func testThrowableNewCreatesThrowable() {
        let msg = makeRuntimeString("error occurred")
        let throwable = __kk_throwable_new(msg)
        #expect(throwable as UnsafeMutableRawPointer? != nil)
        let output = capturePrintln { kk_println_any(throwable) }
        #expect(output.contains("error occurred"))
    }

    @Test
    func testThrowableNewWithNilUsesDefaultMessage() {
        let throwable = __kk_throwable_new(nil)
        #expect(throwable as UnsafeMutableRawPointer? != nil)
        let output = capturePrintln { kk_println_any(throwable) }
        #expect(output.contains("Throwable"))
    }

    @Test
    func testThrowableIsCancellationReturnsFalseForNil() {
        #expect(kk_throwable_is_cancellation(0) == 0)
    }

    @Test
    func testThrowableIsCancellationReturnsFalseForRegularThrowable() {
        let throwable = __kk_throwable_new(makeRuntimeString("not cancellation"))
        let raw = Int(bitPattern: throwable)
        #expect(kk_throwable_is_cancellation(raw) == 0)
    }

    @Test
    func testThrowableAddSuppressedPreservesInsertionOrder() {
        let primary = Int(bitPattern: __kk_throwable_new(makeRuntimeString("primary")))
        let suppressed1 = Int(bitPattern: __kk_throwable_new(makeRuntimeString("suppressed1")))
        let suppressed2 = Int(bitPattern: __kk_throwable_new(makeRuntimeString("suppressed2")))

        _ = __kk_throwable_appendSuppressed(primary, suppressed1)
        _ = __kk_throwable_appendSuppressed(primary, suppressed2)

        let suppressed = __kk_throwable_suppressedRaw(primary)
        #expect(kk_array_size(suppressed) == 2)

        var thrown = 0
        #expect(kk_array_get(suppressed, 0, &thrown) == suppressed1)
        #expect(thrown == 0)
        #expect(kk_array_get(suppressed, 1, &thrown) == suppressed2)
        #expect(thrown == 0)
    }

    @Test
    func testThrowableAddSuppressedRejectsSelfSuppression() {
        let primary = Int(bitPattern: __kk_throwable_new(makeRuntimeString("primary")))

        _ = __kk_throwable_appendSuppressed(primary, primary)

        let suppressed = __kk_throwable_suppressedRaw(primary)
        #expect(kk_array_size(suppressed) == 0)
    }

    @Test
    func testThrowableAddSuppressedIgnoresNullAndInvalidHandles() {
        let primary = Int(bitPattern: __kk_throwable_new(makeRuntimeString("primary")))

        _ = __kk_throwable_appendSuppressed(primary, runtimeNullSentinelInt)
        _ = __kk_throwable_appendSuppressed(primary, 0)
        _ = __kk_throwable_appendSuppressed(primary, 123456789)
        _ = __kk_throwable_appendSuppressed(runtimeNullSentinelInt, primary)
        _ = __kk_throwable_appendSuppressed(123456789, primary)

        let suppressed = __kk_throwable_suppressedRaw(primary)
        #expect(kk_array_size(suppressed) == 0)
    }

    @Test
    func testThrowableRawStackFramesReturnsMessageHeader() {
        let throwable = Int(bitPattern: __kk_throwable_new(makeRuntimeString("print me")))

        let frames = __kk_throwable_rawStackFrames(throwable)
        #expect(kk_array_size(frames) == 1)

        var thrown = 0
        let frameRaw = kk_array_get(frames, 0, &thrown)
        #expect(thrown == 0)
        #expect(extractString(from: UnsafeMutableRawPointer(bitPattern: frameRaw)) == "print me")
    }

    @Test
    func testPrintStderrWritesMessageToStandardError() {
        let message = rawFromRuntimeString("print me")

        let output = captureStandardError {
            #expect(__kk_printStderr(message) == 0)
        }

        #expect(output == "print me")
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
        let array = kk_array_of_nulls(3)
        #expect(array != 0)
        #expect(kk_array_size(array) == 3)

        var thrown = 0
        #expect(kk_array_get(array, 0, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
        #expect(kk_array_get(array, 1, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
        #expect(kk_array_get(array, 2, &thrown) == runtimeNullSentinelInt)
        #expect(thrown == 0)
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

    // MARK: - STDLIB-TEXT-FN-115: String.withIndex()

    @Test
    func testStringWithIndexReturnsListOfIndexedValues() {
        let resultRaw = withFlatString("abc") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        #expect(list != nil, "withIndex should return a list")
        #expect(list?.elements.count == 3)
    }

    @Test
    func testStringWithIndexElementsAreIndexedValuePairs() {
        let resultRaw = withFlatString("ab") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        #expect(list != nil)

        let elements = list?.elements ?? []
        #expect(elements.count == 2)

        // First element: IndexedValue(index=0, value='a')
        #expect(kk_pair_first(elements[0]) == 0)
        #expect(kk_unbox_char(kk_pair_second(elements[0])) == 97) // 'a'

        // Second element: IndexedValue(index=1, value='b')
        #expect(kk_pair_first(elements[1]) == 1)
        #expect(kk_unbox_char(kk_pair_second(elements[1])) == 98) // 'b'
    }

    @Test
    func testStringWithIndexEmptyStringReturnsEmptyList() {
        let resultRaw = withFlatString("") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        #expect(list != nil)
        #expect(list?.elements.count == 0)
    }

    @Test
    func testStringWithIndexNonASCIICharsGetCorrectIndices() {
        let resultRaw = withFlatString("aé🐻") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        #expect(list != nil)
        #expect(list?.elements.count == 4)

        let expectedIndices = [0, 1, 2, 3]
        let expectedCodeUnits = [97, 233, 0xD83D, 0xDC3B] // 'a', 'é', high surrogate, low surrogate
        for (i, elem) in (list?.elements ?? []).enumerated() {
            #expect(kk_pair_first(elem) == expectedIndices[i], "Index mismatch at \(i)")
            #expect(kk_unbox_char(kk_pair_second(elem)) == expectedCodeUnits[i], "Code unit mismatch at \(i)")
        }
    }

    // MARK: - Helpers

    private func makeRuntimeString(_ value: String) -> UnsafeMutableRawPointer {
        value.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: max(1, value.utf8.count)) { ptr in
                kk_string_from_utf8(ptr, Int32(value.utf8.count))
            }
        }
    }

    private func rawFromRuntimeString(_ value: String) -> Int {
        Int(bitPattern: makeRuntimeString(value))
    }

    private func kk_println_any(_ value: Int) {
        __kk_print_raw(rawFromRuntimeString(runtimeRenderAnyForPrint(value) + "\n"))
    }

    private func kk_println_any(_ value: UnsafeMutableRawPointer?) {
        kk_println_any(Int(bitPattern: value))
    }

    private func makeRuntimeArray(_ values: [Int]) -> Int {
        let array = kk_array_new(values.count)
        var thrown = 0
        for (index, value) in values.enumerated() {
            _ = kk_array_set(array, index, value, &thrown)
            #expect(thrown == 0)
        }
        return array
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

    private func makeRuntimeStringValueArray(_ values: [String]) -> Int {
        makeRuntimeValueArray(values.map(runtimeStringAggregateValue))
    }

    private func makeRuntimeValueList(_ values: [RuntimeValue]) -> Int {
        registerRuntimeObject(RuntimeListBox(values: values))
    }

    private func assertFindAnyOfPair(
        _ pairRaw: Int,
        offset: Int,
        match: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        #expect(pairRaw != runtimeNullSentinelInt)
        guard pairRaw != runtimeNullSentinelInt,
              let pairPtr = UnsafeMutableRawPointer(bitPattern: pairRaw),
              let pairBox = tryCast(pairPtr, to: RuntimePairBox.self)
        else {
            Issue.record("Expected RuntimePairBox result")
            return
        }
        #expect(pairBox.firstValue.tag == RuntimeValue.rawTag)
        #expect(pairBox.firstValue.payload0 == offset)
        #expect(pairBox.secondValue.tag == RuntimeValue.stringTag)
        #expect(runtimeRenderAnyForPrint(pairBox.secondValue) == match)
        #expect(kk_pair_first(pairRaw) == offset)
        #expect(runtimeStringFromRawOrPanic(kk_pair_second(pairRaw), caller: #function) == match)
    }

    private func assertStringValueSequence(
        _ sequenceRaw: Int,
        equals expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let sequence = runtimeSequenceBox(from: sequenceRaw) else {
            Issue.record("Expected a RuntimeSequenceBox")
            return
        }
        guard case let .valueSource(values)? = sequence.steps.first else {
            Issue.record("Expected aggregate RuntimeValue sequence source")
            return
        }
        #expect(values.map(\.tag) == Array(repeating: RuntimeValue.stringTag, count: expected.count))
        #expect(runtimeSequenceSourceElements(from: sequenceRaw)?.map(runtimeStringValue) == expected)
    }

    private func assertRawValueSequence(
        _ sequenceRaw: Int,
        equals expected: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let sequence = runtimeSequenceBox(from: sequenceRaw) else {
            Issue.record("Expected a RuntimeSequenceBox")
            return
        }
        guard case let .valueSource(values)? = sequence.steps.first else {
            Issue.record("Expected aggregate RuntimeValue sequence source")
            return
        }
        #expect(values.map(\.tag) == Array(repeating: RuntimeValue.rawTag, count: expected.count))
        #expect(values.map(\.payload0) == expected)
        #expect(runtimeSequenceSourceElements(from: sequenceRaw) == expected)
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

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }

    private func runtimeFlatStringValue(_ value: RuntimeValue) -> String {
        guard value.tag == RuntimeValue.stringTag,
              let data = UnsafePointer<UInt8>(bitPattern: value.payload0)
        else {
            return ""
        }
        return runtimeStringFromFlatFields(
            data: data,
            length: value.payload1,
            byteCount: value.payload2,
            hash: value.payload3
        )
    }
}
#endif
