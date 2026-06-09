@testable import Runtime
import XCTest

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
private typealias RuntimeFlatStringReturnWithStringEntry = (
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    UnsafePointer<UInt8>?,
    Int,
    Int,
    Int,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?,
    UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>?
private typealias RuntimeFlatStringReturnWithStringBoolEntry = (
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

private let runtimeReplaceFirstCharWithUppercaseB: RuntimeStringUnaryEntry = { _, _, _ in
    kk_box_char(Int(Character("B").unicodeScalars.first!.value))
}

private let runtimeReplaceFirstCharWithInvalidScalar: RuntimeStringUnaryEntry = { _, _, _ in
    Int.max
}

private let runtimeReplaceFirstCharThrowing: RuntimeStringUnaryEntry = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "replaceFirstChar failure")
    return 0
}

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
}

private let runtimeFlatStringDigitPredicate: RuntimeStringUnaryEntry = { _, charRaw, _ in
    (0x30 ... 0x39).contains(charRaw) ? 1 : 0
}

private let runtimeFlatStringLowercasePredicate: RuntimeStringUnaryEntry = { _, charRaw, _ in
    (0x61 ... 0x7A).contains(charRaw) ? 1 : 0
}

private let runtimeFlatStringThrowingPredicate: RuntimeStringUnaryEntry = { _, _, outThrown in
    outThrown?.pointee = runtimeAllocateThrowable(message: "flat predicate failure")
    return 0
}

private let runtimeFlatStringLengthTransform: RuntimeStringUnaryEntry = { _, strRaw, _ in
    runtimeStringFromRawOrPanic(strRaw, caller: "runtimeFlatStringLengthTransform").count
}

private let runtimeReturnValueTransform: RuntimeStringUnaryEntry = { _, valueRaw, _ in
    valueRaw
}

final class RuntimeStringArrayTests: IsolatedRuntimeXCTestCase {
    // swiftlint:disable:next static_over_final_class
    override class var requiredLockSet: RuntimeLockSet { .gcOnly }
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
        other: String,
        using call: RuntimeFlatStringReturnWithStringEntry
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            withFlatString(other) { otherData, otherLength, otherByteCount, otherHash in
                var outLength = 0
                var outByteCount = 0
                var outHash = 0
                let outData = call(
                    data,
                    length,
                    byteCount,
                    hash,
                    otherData,
                    otherLength,
                    otherByteCount,
                    otherHash,
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

    private func flatStringReturnValue(
        _ value: String,
        other: String,
        ignoreCase: Bool,
        using call: RuntimeFlatStringReturnWithStringBoolEntry
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            withFlatString(other) { otherData, otherLength, otherByteCount, otherHash in
                var outLength = 0
                var outByteCount = 0
                var outHash = 0
                let outData = call(
                    data,
                    length,
                    byteCount,
                    hash,
                    otherData,
                    otherLength,
                    otherByteCount,
                    otherHash,
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

    private func flatStringSubstringValue(
        _ value: String,
        start: Int,
        end: Int,
        hasEnd: Int = 1,
        outThrown: UnsafeMutablePointer<Int>? = nil
    ) -> String {
        withFlatString(value) { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = kk_string_substring_flat(
                data,
                length,
                byteCount,
                hash,
                start,
                end,
                hasEnd,
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

    func testStringFromUTF8CreatesBoxedString() {
        let text = "Hello"
        let result = text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: text.utf8.count) { ptr in
                kk_string_from_utf8(ptr, Int32(text.utf8.count))
            }
        }
        XCTAssertNotNil(result)
        // Verify via println
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "Hello")
    }

    func testStringFromUTF8EmptyString() {
        let text = ""
        let result = text.withCString { cstr in
            cstr.withMemoryRebound(to: UInt8.self, capacity: 1) { ptr in
                kk_string_from_utf8(ptr, 0)
            }
        }
        XCTAssertNotNil(result)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "")
    }

    // MARK: - kk_string_concat_flat

    func testStringConcatFlatTwoStrings() {
        XCTAssertEqual(concatFlatValue("Hello, ", "World!"), "Hello, World!")
    }

    func testStringConcatFlatWithNilDataLeftReturnsRightOnly() {
        XCTAssertEqual(concatFlatValue(nil, "World"), "World")
    }

    func testStringConcatFlatWithNilDataRightReturnsLeftOnly() {
        XCTAssertEqual(concatFlatValue("Hello", nil), "Hello")
    }

    func testStringConcatFlatBothNilDataReturnsEmptyString() {
        XCTAssertEqual(concatFlatValue(nil, nil), "")
    }

    // MARK: - kk_string_compareTo_flat

    func testStringCompareToFlatEqual() {
        withFlatString("abc") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("abc") { rhsData, rhsLength, rhsByteCount, rhsHash in
                XCTAssertEqual(
                    kk_string_compareTo_flat(
                        lhsData,
                        lhsLength,
                        lhsByteCount,
                        lhsHash,
                        rhsData,
                        rhsLength,
                        rhsByteCount,
                        rhsHash
                    ),
                    0
                )
            }
        }
    }

    func testStringCompareToFlatLessThan() {
        withFlatString("abc") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("xyz") { rhsData, rhsLength, rhsByteCount, rhsHash in
                XCTAssertEqual(
                    kk_string_compareTo_flat(
                        lhsData,
                        lhsLength,
                        lhsByteCount,
                        lhsHash,
                        rhsData,
                        rhsLength,
                        rhsByteCount,
                        rhsHash
                    ),
                    -23
                )
            }
        }
    }

    func testStringCompareToFlatGreaterThan() {
        withFlatString("xyz") { lhsData, lhsLength, lhsByteCount, lhsHash in
            withFlatString("abc") { rhsData, rhsLength, rhsByteCount, rhsHash in
                XCTAssertEqual(
                    kk_string_compareTo_flat(
                        lhsData,
                        lhsLength,
                        lhsByteCount,
                        lhsHash,
                        rhsData,
                        rhsLength,
                        rhsByteCount,
                        rhsHash
                    ),
                    23
                )
            }
        }
    }

    func testStringCompareToFlatNullDataAsEmpty() {
        XCTAssertEqual(
            kk_string_compareTo_flat(nil, 0, 0, 0, nil, 0, 0, 0),
            0
        )
    }

    func testCompareAnyDecodesBoxedDoubleValues() {
        let lhs = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 1.25.bitPattern)))
        let rhs = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern)))

        XCTAssertEqual(kk_compare_any(lhs, rhs), -1)
        XCTAssertEqual(kk_compare_any(rhs, lhs), 1)
    }

    func testCompareAnyPromotesMixedFloatingAndIntegerValues() {
        let lhs = kk_box_float(Int(Float(3).bitPattern))

        XCTAssertEqual(kk_compare_any(lhs, 5), -1)
        XCTAssertEqual(kk_compare_any(5, lhs), 1)
        XCTAssertEqual(kk_compare_any(lhs, 3), 0)
    }

    func testCompareAnyOrdersNaNAfterNonNaNValues() {
        let nan = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: Double.nan.bitPattern)))
        let finite = kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 4.0.bitPattern)))

        XCTAssertEqual(kk_compare_any(nan, finite), 1)
        XCTAssertEqual(kk_compare_any(finite, nan), -1)
        XCTAssertEqual(kk_compare_any(nan, nan), 0)
    }

    func testFloatFormattingUsesKotlinSpecialValueSpellings() {
        XCTAssertEqual(runtimeFormatFloatingPoint(Float.nan), "NaN")
        XCTAssertEqual(runtimeFormatFloatingPoint(Float.infinity), "Infinity")
        XCTAssertEqual(runtimeFormatFloatingPoint(-Float.infinity), "-Infinity")
    }

    func testDoubleFormattingUsesShortestScientificRepresentation() {
        XCTAssertEqual(runtimeFormatFloatingPoint(1e-4), "1.0E-4")
        XCTAssertEqual(runtimeFormatFloatingPoint(1e7), "1.0E7")
        XCTAssertEqual(runtimeFormatFloatingPoint(1.23456789e8), "1.23456789E8")
        XCTAssertEqual(runtimeFormatFloatingPoint(1.0000000000000002e20), "1.0000000000000002E20")
    }

    // MARK: - STDLIB-006 string runtime ABI

    func testFlatStringTrimRemovesLeadingAndTrailingWhitespace() {
        XCTAssertEqual(flatStringReturnValue("  hello  ", using: kk_string_trim_flat), "hello")
    }

    func testFlatStringTrimReturnsFlattenedStringFields() {
        withFlatString("  hello  ") { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = kk_string_trim_flat(data, length, byteCount, hash, &outLength, &outByteCount, &outHash)
            XCTAssertEqual(
                flatStringValue(
                    data: outData.map { UnsafePointer($0) },
                    length: outLength,
                    byteCount: outByteCount,
                    hash: outHash
                ),
                "hello"
            )
        }
        XCTAssertEqual(flatStringReturnValue("KSwiftK", using: kk_string_lowercase_flat), "kswiftk")
        XCTAssertEqual(flatStringReturnValue("KSwiftK", using: kk_string_uppercase_flat), "KSWIFTK")
        XCTAssertEqual(flatStringReturnValue("abc", using: kk_string_reversed_flat), "cba")
    }

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
            XCTAssertEqual(
                flatStringValue(
                    data: startData.map { UnsafePointer($0) },
                    length: startLength,
                    byteCount: startByteCount,
                    hash: startHash
                ),
                "hello  "
            )

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
            XCTAssertEqual(
                flatStringValue(
                    data: endData.map { UnsafePointer($0) },
                    length: endLength,
                    byteCount: endByteCount,
                    hash: endHash
                ),
                "  hello"
            )
        }
    }

    func testFlatStringSubstringReportsThrownSlot() {
        withFlatString("abc") { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            var thrown = 0
            let outData = kk_string_substring_flat(
                data,
                length,
                byteCount,
                hash,
                4,
                1,
                1,
                &outLength,
                &outByteCount,
                &outHash,
                &thrown
            )
            XCTAssertNotEqual(thrown, 0)
            XCTAssertEqual(
                flatStringValue(
                    data: outData.map { UnsafePointer($0) },
                    length: outLength,
                    byteCount: outByteCount,
                    hash: outHash
                ),
                ""
            )
        }
    }

    func testFlatStringSubSequenceReturnsFlattenedStringFields() {
        withFlatString("aé🐻z") { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            let outData = kk_string_subSequence_flat(
                data,
                length,
                byteCount,
                hash,
                1,
                3,
                &outLength,
                &outByteCount,
                &outHash,
                nil
            )
            XCTAssertEqual(
                flatStringValue(
                    data: outData.map { UnsafePointer($0) },
                    length: outLength,
                    byteCount: outByteCount,
                    hash: outHash
                ),
                "é🐻"
            )
        }
    }

    func testFlatStringSubSequenceReportsThrownSlot() {
        withFlatString("abc") { data, length, byteCount, hash in
            var outLength = 0
            var outByteCount = 0
            var outHash = 0
            var thrown = 0
            let outData = kk_string_subSequence_flat(
                data,
                length,
                byteCount,
                hash,
                3,
                1,
                &outLength,
                &outByteCount,
                &outHash,
                &thrown
            )
            XCTAssertNotEqual(thrown, 0)
            XCTAssertEqual(
                flatStringValue(
                    data: outData.map { UnsafePointer($0) },
                    length: outLength,
                    byteCount: outByteCount,
                    hash: outHash
                ),
                ""
            )
        }
    }

    func testFlatStringScalarRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("KSwiftK") { data, length, byteCount, hash in
            withFlatString("KSw") { prefixData, prefixLength, prefixByteCount, prefixHash in
                XCTAssertEqual(
                    kk_unbox_bool(
                        kk_string_startsWith_flat(
                            data,
                            length,
                            byteCount,
                            hash,
                            prefixData,
                            prefixLength,
                            prefixByteCount,
                            prefixHash
                        )
                    ),
                    1
                )
            }
            withFlatString("swift") { needleData, needleLength, needleByteCount, needleHash in
                XCTAssertEqual(
                    kk_unbox_bool(
                        kk_string_contains_ignoreCase_flat(
                            data,
                            length,
                            byteCount,
                            hash,
                            needleData,
                            needleLength,
                            needleByteCount,
                            needleHash,
                            1
                        )
                    ),
                    1
                )
                XCTAssertEqual(
                    kk_string_indexOf_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        needleData,
                        needleLength,
                        needleByteCount,
                        needleHash,
                        0,
                        1
                    ),
                    1
                )
                XCTAssertEqual(
                    kk_string_lastIndexOf_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        needleData,
                        needleLength,
                        needleByteCount,
                        needleHash,
                        length,
                        1
                    ),
                    1
                )
                XCTAssertEqual(
                    kk_string_compareToIgnoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        needleData,
                        needleLength,
                        needleByteCount,
                        needleHash,
                        1
                    ),
                    -1
                )
            }
            withFlatString("") { emptyData, emptyLength, emptyByteCount, emptyHash in
                XCTAssertEqual(
                    kk_string_indexOf_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        emptyData,
                        emptyLength,
                        emptyByteCount,
                        emptyHash,
                        length + 1,
                        0
                    ),
                    length
                )
                XCTAssertEqual(
                    kk_string_indexOf_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        emptyData,
                        emptyLength,
                        emptyByteCount,
                        emptyHash,
                        length + 1,
                        1
                    ),
                    -1
                )
                XCTAssertEqual(
                    kk_string_lastIndexOf_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        emptyData,
                        emptyLength,
                        emptyByteCount,
                        emptyHash,
                        length + 1,
                        0
                    ),
                    length
                )
                XCTAssertEqual(
                    kk_string_lastIndexOf_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        emptyData,
                        emptyLength,
                        emptyByteCount,
                        emptyHash,
                        length + 1,
                        1
                    ),
                    length - 1
                )
            }
            XCTAssertEqual(
                kk_string_indexOf_char_flat(
                    data,
                    length,
                    byteCount,
                    hash,
                    kk_box_char(Int(Unicode.Scalar("s").value)),
                    0,
                    1
                ),
                1
            )
            XCTAssertEqual(
                kk_string_lastIndexOf_char_flat(
                    data,
                    length,
                    byteCount,
                    hash,
                    kk_box_char(Int(Unicode.Scalar("K").value)),
                    length,
                    0
                ),
                6
            )
            XCTAssertEqual(kk_unbox_bool(kk_string_isNotEmpty_flat(data, length, byteCount, hash)), 1)
        }
        withFlatString("  \n\t") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_isBlank_flat(data, length, byteCount, hash)), 1)
            XCTAssertEqual(kk_unbox_bool(kk_string_isNotBlank_flat(data, length, byteCount, hash)), 0)
        }
        withFlatString("") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_isNotEmpty_flat(data, length, byteCount, hash)), 0)
        }
    }

    func testFlatStringIndexOfAnyRuntimeAPIsUseFlattenedStringFields() {
        let charNeedles = makeRuntimeArray([
            kk_box_char(Int(Unicode.Scalar("B").value)),
            kk_box_char(Int(Unicode.Scalar("x").value)),
        ])
        let stringNeedles = makeRuntimeArray([
            rawFromRuntimeString("x"),
            rawFromRuntimeString("bc"),
        ])
        let emptyStringNeedles = makeRuntimeArray([
            rawFromRuntimeString(""),
        ])

        withFlatString("aBcabc") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_indexOfAny_chars_flat(data, length, byteCount, hash, charNeedles, 0, 0),
                1
            )
            XCTAssertEqual(
                kk_string_indexOfAny_chars_flat(data, length, byteCount, hash, charNeedles, 2, 1),
                4
            )
            XCTAssertEqual(
                kk_string_lastIndexOfAny_chars_flat(data, length, byteCount, hash, charNeedles, length, 1),
                4
            )
            XCTAssertEqual(
                kk_string_indexOfAny_strings_flat(data, length, byteCount, hash, stringNeedles, 0, 0),
                4
            )
            XCTAssertEqual(
                kk_string_indexOfAny_strings_flat(data, length, byteCount, hash, stringNeedles, 0, 1),
                1
            )
            XCTAssertEqual(
                kk_string_lastIndexOfAny_strings_flat(data, length, byteCount, hash, stringNeedles, length, 0),
                4
            )
            XCTAssertEqual(
                kk_string_indexOfAny_strings_flat(data, length, byteCount, hash, emptyStringNeedles, 2, 0),
                2
            )
            XCTAssertEqual(
                kk_string_lastIndexOfAny_strings_flat(data, length, byteCount, hash, emptyStringNeedles, 99, 0),
                length
            )
        }

        XCTAssertEqual(kk_string_indexOfAny_chars_flat(nil, 0, 0, 0, charNeedles, 0, 1), -1)
        XCTAssertEqual(kk_string_indexOfAny_strings_flat(nil, 0, 0, 0, emptyStringNeedles, 2, 0), 0)
        XCTAssertEqual(kk_string_lastIndexOfAny_strings_flat(nil, 0, 0, 0, emptyStringNeedles, 2, 0), 0)
    }

    func testFlatStringFindAnyOfRuntimeAPIsUseFlattenedStringFields() {
        let stringNeedles = makeRuntimeArray([
            rawFromRuntimeString("x"),
            rawFromRuntimeString("bc"),
            rawFromRuntimeString("AB"),
        ])
        let emptyStringNeedles = makeRuntimeArray([
            rawFromRuntimeString(""),
        ])

        withFlatString("abcABC") { data, length, byteCount, hash in
            let first = kk_string_findAnyOf_flat(data, length, byteCount, hash, stringNeedles, 0, 0)
            assertFindAnyOfPair(first, offset: 1, match: "bc")

            let afterPrefix = kk_string_findAnyOf_flat(data, length, byteCount, hash, stringNeedles, 3, 0)
            assertFindAnyOfPair(afterPrefix, offset: 3, match: "AB")

            let last = kk_string_findLastAnyOf_flat(data, length, byteCount, hash, stringNeedles, length, 0)
            assertFindAnyOfPair(last, offset: 3, match: "AB")

            let caseInsensitiveNeedles = makeRuntimeArray([
                rawFromRuntimeString("ab"),
            ])
            let caseInsensitive = kk_string_findLastAnyOf_flat(
                data,
                length,
                byteCount,
                hash,
                caseInsensitiveNeedles,
                length,
                1
            )
            assertFindAnyOfPair(caseInsensitive, offset: 3, match: "ab")

            XCTAssertEqual(
                kk_string_findAnyOf_flat(
                    data,
                    length,
                    byteCount,
                    hash,
                    makeRuntimeArray([rawFromRuntimeString("z")]),
                    0,
                    0
                ),
                runtimeNullSentinelInt
            )
        }

        withFlatString("abc") { data, length, byteCount, hash in
            let firstEmpty = kk_string_findAnyOf_flat(data, length, byteCount, hash, emptyStringNeedles, 9, 0)
            assertFindAnyOfPair(firstEmpty, offset: 3, match: "")

            let lastEmpty = kk_string_findLastAnyOf_flat(data, length, byteCount, hash, emptyStringNeedles, -1, 0)
            XCTAssertEqual(lastEmpty, runtimeNullSentinelInt)
        }
    }

    func testFlatStringNullableScalarRuntimeAPIsUseDataNull() {
        XCTAssertEqual(kk_unbox_bool(kk_string_isNullOrEmpty_flat(nil, 0, 0, 0)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_isNullOrBlank_flat(nil, 0, 0, 0)), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_contentEquals_flat(nil, 0, 0, 0, nil, 0, 0, 0)), 1)

        withFlatString("") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_isNullOrEmpty_flat(data, length, byteCount, hash)), 1)
            XCTAssertEqual(kk_unbox_bool(kk_string_contentEquals_flat(data, length, byteCount, hash, nil, 0, 0, 0)), 0)
        }

        withFlatString("  \n\t") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_isNullOrBlank_flat(data, length, byteCount, hash)), 1)
        }

        withFlatString("KSwiftK") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_isNullOrBlank_flat(data, length, byteCount, hash)), 0)
            XCTAssertEqual(
                kk_unbox_bool(kk_string_equals_flat(data, length, byteCount, hash, nil, 0, 0, 0)),
                0
            )
            XCTAssertEqual(
                kk_unbox_bool(kk_string_equalsIgnoreCase_flat(data, length, byteCount, hash, nil, 0, 0, 0, 1)),
                0
            )
            withFlatString("kswiftk") { otherData, otherLength, otherByteCount, otherHash in
                XCTAssertEqual(
                    kk_unbox_bool(
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
                    ),
                    0
                )
                XCTAssertEqual(
                    kk_unbox_bool(
                        kk_string_contentEquals_ignoreCase_flat(
                            data,
                            length,
                            byteCount,
                            hash,
                            otherData,
                            otherLength,
                            otherByteCount,
                            otherHash,
                            1
                        )
                    ),
                    1
                )
                XCTAssertEqual(
                    kk_unbox_bool(
                        kk_string_equalsIgnoreCase_flat(
                            data,
                            length,
                            byteCount,
                            hash,
                            otherData,
                            otherLength,
                            otherByteCount,
                            otherHash,
                            1
                        )
                    ),
                    1
                )
            }
            withFlatString("KSwiftK") { sameData, sameLength, sameByteCount, sameHash in
                XCTAssertEqual(
                    kk_unbox_bool(
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
                    ),
                    1
                )
            }
        }
    }

    func testFlatStringBooleanRuntimeAPIsReturnRawScalars() {
        XCTAssertEqual(kk_string_isNullOrEmpty_flat(nil, 0, 0, 0), 1)
        XCTAssertEqual(kk_string_isNullOrBlank_flat(nil, 0, 0, 0), 1)
        XCTAssertEqual(kk_string_contentEquals_flat(nil, 0, 0, 0, nil, 0, 0, 0), 1)
        XCTAssertEqual(kk_string_toBoolean_flat(nil, 0, 0, 0), 0)

        withFlatString("KSwiftK") { data, length, byteCount, hash in
            XCTAssertEqual(kk_string_isEmpty_flat(data, length, byteCount, hash), 0)
            XCTAssertEqual(kk_string_isNotEmpty_flat(data, length, byteCount, hash), 1)
            XCTAssertEqual(kk_string_isBlank_flat(data, length, byteCount, hash), 0)
            XCTAssertEqual(kk_string_isNotBlank_flat(data, length, byteCount, hash), 1)
            XCTAssertEqual(kk_string_isNullOrEmpty_flat(data, length, byteCount, hash), 0)
            XCTAssertEqual(kk_string_isNullOrBlank_flat(data, length, byteCount, hash), 0)

            withFlatString("KSw") { prefixData, prefixLength, prefixByteCount, prefixHash in
                XCTAssertEqual(
                    kk_string_startsWith_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        prefixData,
                        prefixLength,
                        prefixByteCount,
                        prefixHash
                    ),
                    1
                )
            }

            withFlatString("iftK") { suffixData, suffixLength, suffixByteCount, suffixHash in
                XCTAssertEqual(
                    kk_string_endsWith_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        suffixData,
                        suffixLength,
                        suffixByteCount,
                        suffixHash
                    ),
                    1
                )
                XCTAssertEqual(
                    kk_string_contains_str_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        suffixData,
                        suffixLength,
                        suffixByteCount,
                        suffixHash
                    ),
                    1
                )
            }

            withFlatString("kswiftk") { otherData, otherLength, otherByteCount, otherHash in
                XCTAssertEqual(
                    kk_string_equals_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        otherData,
                        otherLength,
                        otherByteCount,
                        otherHash
                    ),
                    0
                )
                XCTAssertEqual(
                    kk_string_equalsIgnoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        otherData,
                        otherLength,
                        otherByteCount,
                        otherHash,
                        1
                    ),
                    1
                )
                XCTAssertEqual(
                    kk_string_contentEquals_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        otherData,
                        otherLength,
                        otherByteCount,
                        otherHash,
                        1
                    ),
                    1
                )
                XCTAssertEqual(
                    kk_string_contains_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        otherData,
                        otherLength,
                        otherByteCount,
                        otherHash,
                        1
                    ),
                    1
                )
            }
        }

        withFlatString("true") { data, length, byteCount, hash in
            XCTAssertEqual(kk_string_toBoolean_flat(data, length, byteCount, hash), 1)
            XCTAssertEqual(kk_string_toBooleanStrict_flat(data, length, byteCount, hash, nil), 1)
        }

        withFlatString("false") { data, length, byteCount, hash in
            XCTAssertEqual(kk_string_toBooleanStrict_flat(data, length, byteCount, hash, nil), 0)
        }
    }

    func testFlatStringOrEmptyUsesDataNull() {
        var nullLength = -1
        var nullByteCount = -1
        var nullHash = -1
        let nullData = kk_string_orEmpty_flat(nil, 0, 0, 0, &nullLength, &nullByteCount, &nullHash)
        XCTAssertNotNil(nullData)
        XCTAssertEqual(
            flatStringValue(
                data: nullData.map { UnsafePointer($0) },
                length: nullLength,
                byteCount: nullByteCount,
                hash: nullHash
            ),
            ""
        )
        XCTAssertEqual(nullLength, 0)
        XCTAssertEqual(nullByteCount, 0)

        XCTAssertEqual(flatStringReturnValue("hi", using: kk_string_orEmpty_flat), "hi")
    }

    func testFlatStringParseScalarRuntimeAPIsUseFlattenedStringFields() {
        XCTAssertEqual(kk_unbox_bool(kk_string_toBoolean_flat(nil, 0, 0, 0)), 0)

        withFlatString("true") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_toBoolean_flat(data, length, byteCount, hash)), 1)
            XCTAssertEqual(kk_unbox_bool(kk_string_toBooleanStrict_flat(data, length, byteCount, hash, nil)), 1)
            XCTAssertEqual(kk_string_toBooleanStrictOrNull_flat(data, length, byteCount, hash), 1)
        }

        withFlatString("42") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_toInt_flat(data, length, byteCount, hash, &thrown), 42)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_toLong_flat(data, length, byteCount, hash, &thrown), 42)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_toShort_flat(data, length, byteCount, hash, &thrown), 42)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_toByte_flat(data, length, byteCount, hash, &thrown), 42)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_toIntOrNull_flat(data, length, byteCount, hash), 42)
            XCTAssertEqual(kk_string_toLongOrNull_flat(data, length, byteCount, hash), 42)
            XCTAssertEqual(kk_string_toShortOrNull_flat(data, length, byteCount, hash), 42)
            XCTAssertEqual(kk_string_toByteOrNull_flat(data, length, byteCount, hash), 42)
        }

        withFlatString("ff") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_toInt_radix_flat(data, length, byteCount, hash, 16, &thrown), 255)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown), 255)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown), 255)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_toByte_radix_flat(data, length, byteCount, hash, 16, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
        }

        withFlatString("ffff") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(
                kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                Int(UInt16.max)
            )
            XCTAssertEqual(thrown, 0)
        }

        withFlatString("ffffffff") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(
                kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                Int(UInt32.max)
            )
            XCTAssertEqual(thrown, 0)
        }

        withFlatString("ffffffffffffffff") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(
                kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
            )
            XCTAssertEqual(thrown, 0)
        }

        withFlatString("  -Infinity ") { data, length, byteCount, hash in
            var thrown = 0
            let doubleRaw = kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(Double(bitPattern: UInt64(bitPattern: Int64(doubleRaw))), -.infinity)

            let floatRaw = kk_string_toFloat_flat(data, length, byteCount, hash, &thrown)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(Float(bitPattern: UInt32(truncatingIfNeeded: UInt(bitPattern: floatRaw))), -.infinity)
        }

        withFlatString("3.5") { data, length, byteCount, hash in
            XCTAssertNotEqual(kk_string_toDoubleOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
            XCTAssertNotEqual(kk_string_toFloatOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
        }

        withFlatString("nope") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_toInt_flat(data, length, byteCount, hash, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            XCTAssertTrue(thrownOutput.contains("NumberFormatException"))
            XCTAssertEqual(kk_string_toIntOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_toDoubleOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_toFloatOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
        }
    }

    func testFlatStringCharSelectionRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("abc") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_first_flat(data, length, byteCount, hash, &thrown), 97)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_last_flat(data, length, byteCount, hash, &thrown), 99)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_firstOrNull_flat(data, length, byteCount, hash), 97)
            XCTAssertEqual(kk_string_lastOrNull_flat(data, length, byteCount, hash), 99)
            XCTAssertEqual(kk_string_get_flat(data, length, byteCount, hash, 1, &thrown), 98)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_getOrNull_flat(data, length, byteCount, hash, 1), 98)
            XCTAssertEqual(kk_string_getOrNull_flat(data, length, byteCount, hash, -1), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_getOrNull_flat(data, length, byteCount, hash, 3), runtimeNullSentinelInt)

            thrown = 0
            XCTAssertEqual(kk_string_get_flat(data, length, byteCount, hash, 3, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)

            thrown = 0
            XCTAssertEqual(kk_string_single_flat(data, length, byteCount, hash, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            XCTAssertTrue(thrownOutput.contains("more than one element"))
            XCTAssertEqual(kk_string_singleOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
        }

        withFlatString("x") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_single_flat(data, length, byteCount, hash, &thrown), 120)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_singleOrNull_flat(data, length, byteCount, hash), 120)
        }

        withFlatString("") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_first_flat(data, length, byteCount, hash, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
            thrown = 0
            XCTAssertEqual(kk_string_last_flat(data, length, byteCount, hash, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
            thrown = 0
            XCTAssertEqual(kk_string_single_flat(data, length, byteCount, hash, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
            XCTAssertEqual(kk_string_firstOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_lastOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_singleOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
        }
    }

    func testFlatStringCallbackScalarRuntimeAPIsUseFlattenedStringFields() {
        let digitPredicate = unsafeBitCast(runtimeFlatStringDigitPredicate, to: Int.self)
        let lowercasePredicate = unsafeBitCast(runtimeFlatStringLowercasePredicate, to: Int.self)

        withFlatString("a1b2") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_count_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), 2)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_any_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), 1)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_all_flat(data, length, byteCount, hash, lowercasePredicate, 0, &thrown), 0)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_none_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), 0)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_indexOfFirst_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), 1)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_string_indexOfLast_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), 3)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_unbox_char(kk_string_find_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown)), 49)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(
                kk_unbox_char(kk_string_findLast_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown)),
                50
            )
            XCTAssertEqual(thrown, 0)

            XCTAssertEqual(kk_string_count_flat(data, length, byteCount, hash, 0, 0, &thrown), 4)
            XCTAssertEqual(kk_string_any_flat(data, length, byteCount, hash, 0, 0, &thrown), 1)
            XCTAssertEqual(kk_string_all_flat(data, length, byteCount, hash, 0, 0, &thrown), 1)
            XCTAssertEqual(kk_string_none_flat(data, length, byteCount, hash, 0, 0, &thrown), 0)
            XCTAssertEqual(kk_string_find_flat(data, length, byteCount, hash, 0, 0, &thrown), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_findLast_flat(data, length, byteCount, hash, 0, 0, &thrown), runtimeNullSentinelInt)
        }

        withFlatString("") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_string_count_flat(data, length, byteCount, hash, 0, 0, &thrown), 0)
            XCTAssertEqual(kk_string_any_flat(data, length, byteCount, hash, 0, 0, &thrown), 0)
            XCTAssertEqual(kk_string_all_flat(data, length, byteCount, hash, 0, 0, &thrown), 1)
            XCTAssertEqual(kk_string_none_flat(data, length, byteCount, hash, 0, 0, &thrown), 1)
            XCTAssertEqual(kk_string_indexOfFirst_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), -1)
            XCTAssertEqual(kk_string_indexOfLast_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), -1)
            XCTAssertEqual(kk_string_find_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_findLast_flat(data, length, byteCount, hash, digitPredicate, 0, &thrown), runtimeNullSentinelInt)
            XCTAssertEqual(thrown, 0)
        }

        withFlatString("abc") { data, length, byteCount, hash in
            let throwingPredicate = unsafeBitCast(runtimeFlatStringThrowingPredicate, to: Int.self)
            var thrown = 0
            XCTAssertEqual(kk_string_count_flat(data, length, byteCount, hash, throwingPredicate, 0, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            XCTAssertTrue(thrownOutput.contains("flat predicate failure"))

            thrown = 0
            XCTAssertEqual(kk_string_indexOfFirst_flat(data, length, byteCount, hash, throwingPredicate, 0, &thrown), -1)
            XCTAssertNotEqual(thrown, 0)

            thrown = 0
            XCTAssertEqual(
                kk_string_find_flat(data, length, byteCount, hash, throwingPredicate, 0, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertNotEqual(thrown, 0)
        }
    }

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
        XCTAssertEqual(list?.elements.count, 3)
        XCTAssertEqual(list?.elements.map(runtimeStringValue), ["1", "2", "3"])
    }



    func testStringToListAndToCharArrayReturnCharElements() {
        withFlatString("abc") { data, length, byteCount, hash in
            let listRaw = kk_string_toList_flat(data, length, byteCount, hash)
            let charArrayRaw = kk_string_toCharArray_flat(data, length, byteCount, hash)

            let list = runtimeListBox(from: listRaw)
            let charArray = runtimeArrayBox(from: charArrayRaw)
            XCTAssertNotNil(list)
            XCTAssertNotNil(charArray)
            let expected = [97, 98, 99]
            XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
            XCTAssertEqual(charArray?.values.map(\.tag), [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            XCTAssertEqual(charArray?.values.map(\.payload0), expected)
            XCTAssertEqual(charArray?.elements, expected)
            XCTAssertEqual(charArray?.elements.map(kk_unbox_char), expected)
        }
    }

    func testStringToCharArrayStoresTaggedUTF16CodeUnits() {
        withFlatString("hi") { data, length, byteCount, hash in
            let charArrayRaw = kk_string_toCharArray_flat(data, length, byteCount, hash)
            let charArray = runtimeArrayBox(from: charArrayRaw)

            XCTAssertEqual(charArray?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
            XCTAssertEqual(charArray?.values.map(\.payload0), [104, 105])
            XCTAssertEqual(charArray?.elements, [104, 105])
        }
    }

    // MARK: - STDLIB-TEXT-FN-109: String.toTypedArray()

    func testStringToTypedArrayStoresTaggedGenericCharArray() {
        withFlatString("abc") { data, length, byteCount, hash in
            let arrayRaw = kk_string_toTypedArray_flat(data, length, byteCount, hash)
            let array = runtimeArrayBox(from: arrayRaw)
            XCTAssertNotNil(array, "toTypedArray should return a RuntimeArrayBox")
            let expected = [97, 98, 99] // 'a', 'b', 'c'
            XCTAssertEqual(array?.values.map(\.tag), [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            XCTAssertEqual(array?.elements.count, 3)
            XCTAssertEqual(array?.elements.map(kk_unbox_char), expected)
        }
    }

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

            XCTAssertEqual(list?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
            XCTAssertEqual(charArray?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
            XCTAssertEqual(typedArray?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
            XCTAssertEqual(typedArrayList?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
            XCTAssertEqual(list?.elements, [97, 98])
            XCTAssertEqual(charArray?.elements, [97, 98])
            XCTAssertEqual(typedArray?.elements, [97, 98])
            XCTAssertEqual(runtimeRenderAnyForPrint(listRaw), "[a, b]")
            XCTAssertEqual(runtimeRenderAnyForPrint(charArrayRaw), "[a, b]")
            XCTAssertEqual(runtimeRenderAnyForPrint(typedArrayRaw), "[a, b]")
            XCTAssertEqual(runtimeRenderAnyForPrint(typedArrayListRaw), "[a, b]")
        }
    }

    func testStringToTypedArrayEmptyStringReturnsEmptyArray() {
        withFlatString("") { data, length, byteCount, hash in
            let arrayRaw = kk_string_toTypedArray_flat(data, length, byteCount, hash)
            let array = runtimeArrayBox(from: arrayRaw)
            XCTAssertNotNil(array, "toTypedArray on empty string should return a RuntimeArrayBox")
            XCTAssertEqual(array?.elements.count, 0)
        }
    }

    func testStringToTypedArrayIsDistinctFromToCharArray() {
        withFlatString("hi") { data, length, byteCount, hash in
            let typedArrayRaw = kk_string_toTypedArray_flat(data, length, byteCount, hash)
            let charArrayRaw = kk_string_toCharArray_flat(data, length, byteCount, hash)
            // Both should decode to the same char values but are distinct array objects
            let typedArray = runtimeArrayBox(from: typedArrayRaw)
            let charArray = runtimeArrayBox(from: charArrayRaw)
            XCTAssertNotNil(typedArray)
            XCTAssertNotNil(charArray)
            let expected = [104, 105] // 'h', 'i'
            XCTAssertEqual(typedArray?.elements.map(kk_unbox_char), expected)
            XCTAssertEqual(charArray?.elements.map(kk_unbox_char), expected)
            XCTAssertNotEqual(typedArrayRaw, charArrayRaw, "toTypedArray and toCharArray should return distinct array handles")
        }
    }

    // MARK: - STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)

    func testStringToCollectionAppendsCharsToMutableList() {
        let returnedRaw = withFlatString("abc") { data, length, byteCount, hash in
            let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
            let returnedRaw = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)

            XCTAssertEqual(returnedRaw, destRaw, "toCollection should return the destination collection")
            return returnedRaw
        }
        let list = runtimeListBox(from: returnedRaw)
        XCTAssertNotNil(list)
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        XCTAssertEqual(list?.values.map(\.tag), [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringToCollectionPreservesExistingElements() {
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: [kk_box_char(97)]))
        withFlatString("de") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let list = runtimeListBox(from: destRaw)
        let expected = [97, 100, 101] // 'a', 'd', 'e'
        XCTAssertEqual(list?.values.map(\.tag), [
            RuntimeValue.rawTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringToCollectionEmptyStringLeavesDestinationUnchanged() {
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        withFlatString("") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let list = runtimeListBox(from: destRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testStringToCollectionWithNonASCII() {
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        withFlatString("aé🐻") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let list = runtimeListBox(from: destRaw)
        let expected = [97, 233, 0xD83D, 0xDC3B]
        XCTAssertEqual(
            list?.values.map(\.tag),
            [RuntimeValue.charTag, RuntimeValue.charTag, RuntimeValue.charTag, RuntimeValue.charTag]
        )
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringToCollectionFlatAppendsCharsToMutableList() {
        withFlatString("az") { data, length, byteCount, hash in
            let destRaw = registerRuntimeObject(RuntimeListBox(elements: [kk_box_char(48)]))
            let returnedRaw = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)

            XCTAssertEqual(returnedRaw, destRaw, "flat toCollection should return the destination collection")
            let list = runtimeListBox(from: returnedRaw)
            let expected = [48, 97, 122] // '0', 'a', 'z'
            XCTAssertEqual(list?.values.map(\.tag), [
                RuntimeValue.rawTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
        }
    }

    func testStringToCollectionDeduplicatesTaggedCharsInMutableSet() {
        let destRaw = registerRuntimeObject(RuntimeSetBox(elements: [kk_box_char(97)]))
        withFlatString("aab") { data, length, byteCount, hash in
            _ = kk_string_toCollection_flat(data, length, byteCount, hash, destRaw)
        }

        let set = runtimeSetBox(from: destRaw)
        XCTAssertEqual(set?.values.map(\.tag), [RuntimeValue.rawTag, RuntimeValue.charTag])
        XCTAssertEqual(set?.elements.map(kk_unbox_char), [97, 98])
    }

    func testListToCharArrayStoresTaggedCharCodeUnits() {
        let listRaw = registerRuntimeObject(RuntimeListBox(values: [
            RuntimeValue(raw: kk_box_char(97)),
            RuntimeValue(charScalar: 233),
        ]))
        let charArrayRaw = kk_list_toCharArray(listRaw)
        let charArray = runtimeArrayBox(from: charArrayRaw)

        XCTAssertEqual(charArray?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(charArray?.values.map(\.payload0), [97, 233])
        XCTAssertEqual(charArray?.elements, [97, 233])
        XCTAssertEqual(charArray?.elements.map(kk_unbox_char), [97, 233])
    }

    // MARK: - STDLIB-TEXT-FN-108: kk_string_toSortedSet_flat tests

    func testStringToSortedSetReturnsSortedUniqueChars() {
        // "cba" should produce {a, b, c} sorted ascending
        let setRaw = withFlatString("cba") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.values.map(\.tag), [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(setBox?.elements.map(kk_unbox_char), [97, 98, 99]) // a, b, c
    }

    func testStringToSortedSetDeduplicates() {
        // "aabba" — unique chars are 'a'(97) and 'b'(98) in ascending order
        let setRaw = withFlatString("aabba") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(setBox?.elements.map(kk_unbox_char), [97, 98]) // a, b
    }

    func testStringToSortedSetEmptyString() {
        let setRaw = withFlatString("") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.elements.count, 0)
    }

    func testStringToSortedSetSingleChar() {
        let setRaw = withFlatString("z") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.values.map(\.tag), [RuntimeValue.charTag])
        XCTAssertEqual(setBox?.elements.map(kk_unbox_char), [122]) // 'z'
    }

    func testStringToSortedSetUsesUTF16CodeUnits() {
        let setRaw = withFlatString("a🐻a") { data, length, byteCount, hash in
            kk_string_toSortedSet_flat(data, length, byteCount, hash)
        }
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.values.map(\.tag), [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(setBox?.elements.map(kk_unbox_char), [97, 0xD83D, 0xDC3B])
    }

    func testFlatStringMaterializationRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("abc") { data, length, byteCount, hash in
            let expected = [97, 98, 99]

            let list = runtimeListBox(from: kk_string_toList_flat(data, length, byteCount, hash))
            let charArray = runtimeArrayBox(from: kk_string_toCharArray_flat(data, length, byteCount, hash))
            let typedArray = runtimeArrayBox(from: kk_string_toTypedArray_flat(data, length, byteCount, hash))

            XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
            XCTAssertEqual(charArray?.elements.map(kk_unbox_char), expected)
            XCTAssertEqual(typedArray?.elements.map(kk_unbox_char), expected)
        }

        withFlatString("a🐻a") { data, length, byteCount, hash in
            let expected = [97, 0xD83D, 0xDC3B, 97]
            let list = runtimeListBox(from: kk_string_toList_flat(data, length, byteCount, hash))
            let charArray = runtimeArrayBox(from: kk_string_toCharArray_flat(data, length, byteCount, hash))
            let typedArray = runtimeArrayBox(from: kk_string_toTypedArray_flat(data, length, byteCount, hash))
            let sortedSet = runtimeSetBox(from: kk_string_toSortedSet_flat(data, length, byteCount, hash))
            XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
            XCTAssertEqual(charArray?.elements.map(kk_unbox_char), expected)
            XCTAssertEqual(typedArray?.elements.map(kk_unbox_char), expected)
            XCTAssertEqual(sortedSet?.elements.map(kk_unbox_char), [97, 0xD83D, 0xDC3B])
        }

        withFlatString("ab") { data, length, byteCount, hash in
            let withIndex = runtimeListBox(from: kk_string_withIndex_flat(data, length, byteCount, hash))
            let elements = withIndex?.elements ?? []
            XCTAssertEqual(elements.count, 2)
            XCTAssertEqual(kk_pair_first(elements[0]), 0)
            XCTAssertEqual(kk_unbox_char(kk_pair_second(elements[0])), 97)
            XCTAssertEqual(kk_pair_first(elements[1]), 1)
            XCTAssertEqual(kk_unbox_char(kk_pair_second(elements[1])), 98)

            let iteratorRaw = kk_string_iterator_flat(data, length, byteCount, hash)
            XCTAssertEqual(kk_string_iterator_hasNext(iteratorRaw), 1)
            XCTAssertEqual(kk_unbox_char(kk_string_iterator_next(iteratorRaw)), 97)
            XCTAssertEqual(kk_string_iterator_hasNext(iteratorRaw), 1)
            XCTAssertEqual(kk_unbox_char(kk_string_iterator_next(iteratorRaw)), 98)
            XCTAssertEqual(kk_string_iterator_hasNext(iteratorRaw), 0)
        }

        withFlatString("") { data, length, byteCount, hash in
            XCTAssertEqual(
                runtimeListBox(from: kk_string_toList_flat(data, length, byteCount, hash))?.elements.count,
                0
            )
            XCTAssertEqual(
                runtimeArrayBox(from: kk_string_toCharArray_flat(data, length, byteCount, hash))?.elements.count,
                0
            )
            XCTAssertEqual(
                runtimeArrayBox(from: kk_string_toTypedArray_flat(data, length, byteCount, hash))?.elements.count,
                0
            )
            XCTAssertEqual(
                runtimeSetBox(from: kk_string_toSortedSet_flat(data, length, byteCount, hash))?.elements.count,
                0
            )
            XCTAssertEqual(
                runtimeListBox(from: kk_string_withIndex_flat(data, length, byteCount, hash))?.elements.count,
                0
            )
            XCTAssertEqual(kk_string_iterator_hasNext(kk_string_iterator_flat(data, length, byteCount, hash)), 0)
        }
    }

    // MARK: - STDLIB-317: String.asIterable() tests

    func testStringAsIterableReturnsLazyBox() {
        let iterableRaw = flatStringAsIterable("abc")

        // The iterable should be a RuntimeStringIterableBox, not a list.
        let iterableBox = runtimeStringIterableBox(from: iterableRaw)
        XCTAssertNotNil(iterableBox, "asIterable should return a RuntimeStringIterableBox")
        XCTAssertEqual(iterableBox?.source, "abc", "Box should store the immutable string payload")

        // It should NOT be a list (lazy, not materialised).
        let listBox = runtimeListBox(from: iterableRaw)
        XCTAssertNil(listBox, "asIterable should NOT materialise a list eagerly")
    }

    func testFlatStringListSequenceRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("a\nb\r\nc") { data, length, byteCount, hash in
            let lines = runtimeListBox(from: kk_string_lines_flat(data, length, byteCount, hash))
            XCTAssertEqual(lines?.elements.map(runtimeStringValue), ["a", "b", "c"])

            let lineSequence = kk_string_lineSequence_flat(data, length, byteCount, hash)
            XCTAssertEqual(runtimeSequenceSourceElements(from: lineSequence)?.map(runtimeStringValue), ["a", "b", "c"])
        }

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
                XCTAssertEqual(split?.elements.map(runtimeStringValue), ["a", "b", "c"])

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
                XCTAssertEqual(splitLimit?.elements.map(runtimeStringValue), ["a", "b,c"])

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
                XCTAssertEqual(runtimeSequenceSourceElements(from: splitSequence)?.map(runtimeStringValue), ["a", "b", "c"])
            }
        }

        withFlatString("aé") { data, length, byteCount, hash in
            let iterableRaw = kk_string_asIterable_flat(data, length, byteCount, hash)
            let iterableBox = runtimeStringIterableBox(from: iterableRaw)
            XCTAssertEqual(iterableBox?.source, "aé")
            XCTAssertNil(runtimeListBox(from: iterableRaw), "asIterable should stay lazy on the flat ABI path")
            let list = runtimeListBox(from: kk_string_iterable_toList(iterableRaw))
            XCTAssertEqual(list?.elements.map(kk_unbox_char), [97, 233])
        }

        withFlatString("a🐻") { data, length, byteCount, hash in
            let sequenceRaw = kk_string_asSequence_flat(data, length, byteCount, hash)
            XCTAssertEqual(
                runtimeSequenceSourceElements(from: sequenceRaw)?.map(kk_unbox_char),
                [97, 0xD83D, 0xDC3B]
            )

            let list = runtimeListBox(from: kk_sequence_to_list(sequenceRaw, nil))
            XCTAssertEqual(list?.values.map(\.tag), [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            XCTAssertEqual(list?.elements, [97, 0xD83D, 0xDC3B])

            let mutableList = runtimeListBox(from: kk_sequence_toMutableList(sequenceRaw))
            XCTAssertEqual(mutableList?.values.map(\.tag), [
                RuntimeValue.charTag,
                RuntimeValue.charTag,
                RuntimeValue.charTag,
            ])
            XCTAssertEqual(mutableList?.elements, [97, 0xD83D, 0xDC3B])
        }
    }

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

        XCTAssertEqual(set?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(mutableSet?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(hashSet?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(sortedSet?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(destination?.values.map(\.tag), [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(set?.elements, [97, 98])
        XCTAssertEqual(mutableSet?.elements, [97, 98])
        XCTAssertEqual(hashSet?.elements, [97, 98])
        XCTAssertEqual(sortedSet?.elements, [97, 98])
        XCTAssertEqual(destination?.elements, [97, 98, 97])
    }

    func testFlatStringChunkedWindowedRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("abcde") { data, length, byteCount, hash in
            let chunks = runtimeListBox(from: kk_string_chunked_flat(data, length, byteCount, hash, 2))
            XCTAssertEqual(chunks?.elements.map(runtimeStringValue), ["ab", "cd", "e"])

            let chunkSequence = kk_string_chunked_sequence_flat(data, length, byteCount, hash, 3)
            XCTAssertEqual(runtimeSequenceSourceElements(from: chunkSequence)?.map(runtimeStringValue), ["abc", "de"])

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
            XCTAssertEqual(thrown, 0)
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
            XCTAssertEqual(thrown, 0)
            assertStringValueSequence(transformedChunkStrings, equals: ["ab", "cd", "e"])

            let defaultWindows = runtimeListBox(from: kk_string_windowed_default_flat(data, length, byteCount, hash, 3))
            XCTAssertEqual(defaultWindows?.elements.map(runtimeStringValue), ["abc", "bcd", "cde"])

            let steppedWindows = runtimeListBox(from: kk_string_windowed_flat(data, length, byteCount, hash, 3, 2))
            XCTAssertEqual(steppedWindows?.elements.map(runtimeStringValue), ["abc", "cde"])

            let partialWindows = runtimeListBox(from: kk_string_windowed_partial_flat(data, length, byteCount, hash, 3, 2, 1))
            XCTAssertEqual(partialWindows?.elements.map(runtimeStringValue), ["abc", "cde", "e"])

            let partialWindowSequence = kk_string_windowedSequence_partial_flat(data, length, byteCount, hash, 3, 2, 1)
            XCTAssertEqual(
                runtimeSequenceSourceElements(from: partialWindowSequence)?.map(runtimeStringValue),
                ["abc", "cde", "e"]
            )

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
            XCTAssertEqual(thrown, 0)
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
            XCTAssertEqual(thrown, 0)
            assertStringValueSequence(transformedWindowStrings, equals: ["abc", "cde", "e"])
        }

        withFlatString("") { data, length, byteCount, hash in
            XCTAssertEqual(
                runtimeListBox(from: kk_string_chunked_flat(data, length, byteCount, hash, 2))?.elements.count,
                0
            )
            XCTAssertEqual(
                runtimeListBox(from: kk_string_windowed_default_flat(data, length, byteCount, hash, 2))?.elements.count,
                0
            )
        }
    }

    func testStringAsIterableToListMaterialises() {
        let iterableRaw = flatStringAsIterable("abc")
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        XCTAssertNotNil(list)
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringAsIterableIteratorYieldsCharacters() {
        let iterableRaw = flatStringAsIterable("hi")
        let iterRaw = kk_string_iterable_iterator(iterableRaw)

        XCTAssertEqual(kk_string_iterator_hasNext(iterRaw), 1)
        let first = kk_unbox_char(kk_string_iterator_next(iterRaw))
        XCTAssertEqual(first, 104) // 'h'

        XCTAssertEqual(kk_string_iterator_hasNext(iterRaw), 1)
        let second = kk_unbox_char(kk_string_iterator_next(iterRaw))
        XCTAssertEqual(second, 105) // 'i'

        XCTAssertEqual(kk_string_iterator_hasNext(iterRaw), 0)
    }

    func testStringIteratorNextReturnsRawUTF16CodeUnits() {
        let iterableRaw = flatStringAsIterable("hi")
        let iterRaw = kk_string_iterable_iterator(iterableRaw)

        XCTAssertEqual(kk_string_iterator_next(iterRaw), 104)
        XCTAssertEqual(kk_string_iterator_next(iterRaw), 105)
        XCTAssertEqual(kk_string_iterator_next(iterRaw), 0)
    }

    func testStringAsIterableWithNonASCII() {
        let iterableRaw = flatStringAsIterable("aé🐻")
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        let expectedCodeUnits: [Int] = [97, 233, 0xD83D, 0xDC3B]
        XCTAssertEqual(
            list?.values.map(\.tag),
            Array(repeating: RuntimeValue.charTag, count: expectedCodeUnits.count)
        )
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expectedCodeUnits)

        let iteratorRaw = kk_string_iterable_iterator(iterableRaw)
        XCTAssertEqual(kk_string_iterator_next(iteratorRaw), 97)
        XCTAssertEqual(kk_string_iterator_next(iteratorRaw), 233)
        XCTAssertEqual(kk_string_iterator_next(iteratorRaw), 0xD83D)
        XCTAssertEqual(kk_string_iterator_next(iteratorRaw), 0xDC3B)
        XCTAssertEqual(kk_string_iterator_hasNext(iteratorRaw), 0)
    }

    func testStringAsIterableGenericConversionsPreserveTaggedChars() {
        let iterableRaw = flatStringAsIterable("aba")

        let mutableList = runtimeListBox(from: kk_iterable_toMutableList(iterableRaw))
        let mutableSet = runtimeSetBox(from: kk_iterable_toMutableSet(iterableRaw))
        let hashSet = runtimeSetBox(from: kk_iterable_toHashSet(iterableRaw))

        XCTAssertEqual(mutableList?.values.map(\.tag), [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(mutableList?.elements, [97, 98, 97])
        XCTAssertEqual(mutableSet?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(mutableSet?.elements, [97, 98])
        XCTAssertEqual(hashSet?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(hashSet?.elements, [97, 98])
    }

    func testStringCharCollectionCopiesPreserveTaggedChars() {
        let listRaw = kk_iterable_toMutableList(flatStringAsIterable("aba"))

        let set = runtimeSetBox(from: kk_list_to_set(listRaw))
        let mutableSet = runtimeSetBox(from: kk_list_to_mutable_set(listRaw))
        let hashSet = runtimeSetBox(from: kk_list_toHashSet(listRaw))
        let mutableList = runtimeListBox(from: kk_collection_toMutableList(listRaw))
        let typedArray = runtimeArrayBox(from: kk_collection_toTypedArray(listRaw))

        XCTAssertEqual(set?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(mutableSet?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(hashSet?.values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(mutableList?.values.map(\.tag), [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(typedArray?.values.map(\.tag), [
            RuntimeValue.charTag,
            RuntimeValue.charTag,
            RuntimeValue.charTag,
        ])
        XCTAssertEqual(set?.elements, [97, 98])
        XCTAssertEqual(mutableList?.elements, [97, 98, 97])
        XCTAssertEqual(typedArray?.elements, [97, 98, 97])
    }

    func testStringAsIterableGenericJoinToStringRendersTaggedChars() {
        let iterableRaw = flatStringAsIterable("aé🐻")
        let result = kk_iterable_joinToString(
            iterableRaw,
            rawFromRuntimeString("|"),
            rawFromRuntimeString("<"),
            rawFromRuntimeString(">")
        )

        XCTAssertEqual(runtimeStringValue(Int(bitPattern: result)), "<a|é|?|?>")
    }

    func testStringAsIterableAsSequencePreservesTaggedSourceValues() {
        let sequenceRaw = kk_iterable_asSequence(flatStringAsIterable("ab"))
        let sequence = runtimeSequenceBox(from: sequenceRaw)

        guard case let .valueSource(values)? = sequence?.steps.first else {
            XCTFail("Expected String.asIterable().asSequence() to use RuntimeValue source storage")
            return
        }

        XCTAssertEqual(values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(values.map(\.legacyRawValue), [97, 98])
    }

    func testStringAsIterableEmptyString() {
        let iterableRaw = flatStringAsIterable("")
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testStringIterableHelpersDoNotAcceptLegacyRawStringHandles() {
        let legacyRaw = rawFromRuntimeString("abc")

        let list = runtimeListBox(from: kk_string_iterable_toList(legacyRaw))
        XCTAssertEqual(list?.elements.count, 0)

        let iterator = kk_string_iterable_iterator(legacyRaw)
        XCTAssertEqual(kk_string_iterator_hasNext(iterator), 0)
    }

    func testStringAsIterablePrintDoesNotMaterialiseList() {
        let iterableRaw = flatStringAsIterable("aé🐻")
        let baselineObjectCount = kk_runtime_heap_object_count()

        let output = capturePrintln {
            kk_println_any(UnsafeMutableRawPointer(bitPattern: iterableRaw))
        }

        XCTAssertEqual(output, "[a, é, 🐻]")
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    func testStringAsIterableRenderDoesNotMaterialiseList() {
        let iterableRaw = flatStringAsIterable("abc")
        let baselineObjectCount = kk_runtime_heap_object_count()

        XCTAssertEqual(runtimeRenderAnyForPrint(iterableRaw), "[a, b, c]")
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    func testStringFunctionsWithNonASCII() {
        let text = "aé🐻"
        let listRaw = kk_string_toList(rawFromRuntimeString(text))
        let list = runtimeListBox(from: listRaw)
        let expectedCodeUnits: [Int] = [97, 233, 0xD83D, 0xDC3B]
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expectedCodeUnits)

        XCTAssertEqual(flatStringReturnValue(text, intArg: 2, using: kk_string_take_flat), "aé")
        XCTAssertEqual(flatStringReturnValue(text, intArg: 1, using: kk_string_drop_flat), "é🐻")
    }

    func testCommonPrefixSuffixFlatRuntimeAPIsUseFlattenedStringFields() {
        XCTAssertEqual(
            flatStringReturnValue("alphabet", other: "alpine", using: kk_string_commonPrefixWith_flat),
            "alp"
        )
        XCTAssertEqual(
            flatStringReturnValue("alphabet", other: "bet", using: kk_string_commonSuffixWith_flat),
            "bet"
        )
        XCTAssertEqual(
            flatStringReturnValue(
                "HelloWorld",
                other: "helloKotlin",
                ignoreCase: true,
                using: kk_string_commonPrefixWith_ignoreCase_flat
            ),
            "Hello"
        )
        XCTAssertEqual(
            flatStringReturnValue(
                "HelloWORLD",
                other: "MyWorld",
                ignoreCase: true,
                using: kk_string_commonSuffixWith_ignoreCase_flat
            ),
            "WORLD"
        )
        XCTAssertEqual(
            flatStringReturnValue("aé🐻", other: "aéz", using: kk_string_commonPrefixWith_flat),
            "aé"
        )
        XCTAssertEqual(
            flatStringReturnValue("pre🐻", other: "x🐻", using: kk_string_commonSuffixWith_flat),
            "🐻"
        )
    }

    func testStringScalarIndexedOperationsWithNonASCII() {
        let textRaw = rawFromRuntimeString("aé🐻")

        XCTAssertEqual(runtimeStringValue(kk_string_substring(textRaw, 1, 3, 1, nil)), "é🐻")
        XCTAssertEqual(kk_string_indexOf(textRaw, rawFromRuntimeString("é🐻")), 1)
        XCTAssertEqual(kk_string_lastIndexOf(textRaw, rawFromRuntimeString("é")), 1)
    }

    func testPairAndArrayRenderingStayDistinct() {
        let pairRaw = kk_pair_new(1, 2)
        XCTAssertEqual(runtimeElementToString(pairRaw), "(1, 2)")
        XCTAssertEqual(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: pairRaw)) }, "(1, 2)")

        var thrown = 0
        let arrayRaw = kk_array_new(2)
        _ = kk_array_set(arrayRaw, 0, 1, &thrown)
        _ = kk_array_set(arrayRaw, 1, 2, &thrown)
        XCTAssertEqual(runtimeElementToString(arrayRaw), "[1, 2]")
        XCTAssertEqual(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: arrayRaw)) }, "[1, 2]")
    }

    func testStringTakeDropFunctions() {
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 0, using: kk_string_take_flat), "")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 2, using: kk_string_take_flat), "ab")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 10, using: kk_string_take_flat), "abcde")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 0, using: kk_string_drop_flat), "abcde")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 2, using: kk_string_drop_flat), "cde")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 10, using: kk_string_drop_flat), "")
    }

    func testStringRepeatFlatFunction() {
        XCTAssertEqual(flatStringReturnValue("ab", intArg: 0, using: kk_string_repeat_flat), "")
        XCTAssertEqual(flatStringReturnValue("ab", intArg: 3, using: kk_string_repeat_flat), "ababab")
        XCTAssertEqual(flatStringReturnValue("é", intArg: 2, using: kk_string_repeat_flat), "éé")
    }

    func testStringRepeatFlatNegativeThrowsIllegalArgumentException() {
        var thrown = 0
        _ = flatStringReturnValue("hello", intArg: -1, using: kk_string_repeat_flat, outThrown: &thrown)
        XCTAssertNotEqual(thrown, 0, "kk_string_repeat_flat(-1) should set outThrown")
    }

    func testStringTakeNegativeThrowsIllegalArgumentException() {
        // STDLIB-005-BUG-01: negative count must throw, not silently return empty/full.
        var thrown = 0
        _ = flatStringReturnValue("hello", intArg: -1, using: kk_string_take_flat, outThrown: &thrown)
        XCTAssertNotEqual(thrown, 0, "kk_string_take_flat(-1) should set outThrown")

        var thrown2 = 0
        _ = flatStringReturnValue("hello", intArg: -1, using: kk_string_drop_flat, outThrown: &thrown2)
        XCTAssertNotEqual(thrown2, 0, "kk_string_drop_flat(-1) should set outThrown")
    }

    func testStringTakeLastDropLastFunctions() {
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 0, using: kk_string_takeLast_flat), "")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 2, using: kk_string_takeLast_flat), "de")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 10, using: kk_string_takeLast_flat), "abcde")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 0, using: kk_string_dropLast_flat), "abcde")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 2, using: kk_string_dropLast_flat), "abc")
        XCTAssertEqual(flatStringReturnValue("abcde", intArg: 10, using: kk_string_dropLast_flat), "")
    }

    func testStringTakeLastDropLastNegativeThrowsIllegalArgumentException() {
        // STDLIB-005-BUG-01: negative count must throw, not silently return empty/full.
        var thrown = 0
        _ = flatStringReturnValue("hello", intArg: -1, using: kk_string_takeLast_flat, outThrown: &thrown)
        XCTAssertNotEqual(thrown, 0, "kk_string_takeLast_flat(-1) should set outThrown")

        var thrown2 = 0
        _ = flatStringReturnValue("hello", intArg: -1, using: kk_string_dropLast_flat, outThrown: &thrown2)
        XCTAssertNotEqual(thrown2, 0, "kk_string_dropLast_flat(-1) should set outThrown")
    }

    func testStringReplaceIndentByMarginBlankMarginPrefixThrowsIllegalArgumentException() throws {
        var thrown = 0
        _ = kk_string_replaceIndentByMargin(
            rawFromRuntimeString("|line"),
            rawFromRuntimeString(">"),
            rawFromRuntimeString("   "),
            &thrown
        )
        XCTAssertNotEqual(thrown, 0, "blank marginPrefix should set outThrown")
        let box = try XCTUnwrap(throwableBox(from: thrown))
        XCTAssertEqual(box.exceptionFQName, "kotlin.IllegalArgumentException")
        XCTAssertTrue(box.renderedMessage.contains("marginPrefix must be non-blank string."))
    }

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
                    XCTAssertEqual(
                        flatStringValue(
                            data: result.map { UnsafePointer($0) },
                            length: outLength,
                            byteCount: outByteCount,
                            hash: outHash
                        ),
                        "zbz"
                    )
                }
            }
        }
    }

    // MARK: - STDLIB-TEXT-FN-055: replace overloads

    func testStringReplaceCharReplacesAllOccurrences() {
        let replaced = kk_string_replace_char(
            rawFromRuntimeString("hello world"),
            kk_box_char(Int("l".unicodeScalars.first!.value)),
            kk_box_char(Int("r".unicodeScalars.first!.value))
        )
        XCTAssertEqual(runtimeStringValue(replaced), "herro worrd")
    }

    func testStringReplaceCharHandlesNoMatch() {
        let replaced = kk_string_replace_char(
            rawFromRuntimeString("hello"),
            kk_box_char(Int("z".unicodeScalars.first!.value)),
            kk_box_char(Int("x".unicodeScalars.first!.value))
        )
        XCTAssertEqual(runtimeStringValue(replaced), "hello")
    }

    func testStringReplaceIgnoreCaseCaseSensitiveMatch() {
        let replaced = kk_string_replace_ignoreCase(
            rawFromRuntimeString("Hello World"),
            rawFromRuntimeString("hello"),
            rawFromRuntimeString("Hi"),
            1
        )
        XCTAssertEqual(runtimeStringValue(replaced), "Hi World")
    }

    func testStringReplaceIgnoreCaseCaseSensitiveFalse() {
        let replaced = kk_string_replace_ignoreCase(
            rawFromRuntimeString("Hello World"),
            rawFromRuntimeString("hello"),
            rawFromRuntimeString("Hi"),
            0
        )
        XCTAssertEqual(runtimeStringValue(replaced), "Hello World")
    }

    func testStringReplaceCharIgnoreCaseReplaces() {
        let replaced = kk_string_replace_char_ignoreCase(
            rawFromRuntimeString("Hello World"),
            kk_box_char(Int("h".unicodeScalars.first!.value)),
            kk_box_char(Int("J".unicodeScalars.first!.value)),
            1
        )
        XCTAssertEqual(runtimeStringValue(replaced), "Jello World")
    }

    func testStringReplaceCharIgnoreCaseFalseIsCaseSensitive() {
        let replaced = kk_string_replace_char_ignoreCase(
            rawFromRuntimeString("Hello World"),
            kk_box_char(Int("h".unicodeScalars.first!.value)),
            kk_box_char(Int("J".unicodeScalars.first!.value)),
            0
        )
        XCTAssertEqual(runtimeStringValue(replaced), "Hello World")
    }

    func testStringReplaceFirstCharReplacesOnlyLeadingScalar() {
        let replaced = flatStringReturnValue(
            "abc",
            firstIntArg: unsafeBitCast(runtimeReplaceFirstCharWithUppercaseB, to: Int.self),
            secondIntArg: 0,
            using: kk_string_replaceFirstChar_flat
        )

        XCTAssertEqual(replaced, "Bbc")
    }

    func testStringReplaceFirstCharFallsBackToOriginalScalarForInvalidReplacement() {
        let original = "éclair"
        let replaced = flatStringReturnValue(
            original,
            firstIntArg: unsafeBitCast(runtimeReplaceFirstCharWithInvalidScalar, to: Int.self),
            secondIntArg: 0,
            using: kk_string_replaceFirstChar_flat
        )

        XCTAssertEqual(replaced, original)
    }

    func testStringReplaceFirstCharPropagatesThrownValue() {
        var thrown = -1
        let replaced = flatStringReturnValue(
            "abc",
            firstIntArg: unsafeBitCast(runtimeReplaceFirstCharThrowing, to: Int.self),
            secondIntArg: 0,
            using: kk_string_replaceFirstChar_flat,
            outThrown: &thrown
        )

        XCTAssertEqual(replaced, "")
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("replaceFirstChar failure"))
    }

    func testStringStartsWithEndsWithContains() {
        withFlatString("HelloWorld") { data, length, byteCount, hash in
            withFlatString("Hello") { prefixData, prefixLength, prefixByteCount, prefixHash in
                XCTAssertEqual(
                    kk_unbox_bool(kk_string_startsWith_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        prefixData,
                        prefixLength,
                        prefixByteCount,
                        prefixHash
                    )),
                    1
                )
            }
            withFlatString("World") { suffixData, suffixLength, suffixByteCount, suffixHash in
                XCTAssertEqual(
                    kk_unbox_bool(kk_string_endsWith_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        suffixData,
                        suffixLength,
                        suffixByteCount,
                        suffixHash
                    )),
                    1
                )
                XCTAssertEqual(
                    kk_unbox_bool(kk_string_contains_str_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        suffixData,
                        suffixLength,
                        suffixByteCount,
                        suffixHash
                    )),
                    1
                )
            }
            withFlatString("") { emptyData, emptyLength, emptyByteCount, emptyHash in
                XCTAssertEqual(
                    kk_unbox_bool(kk_string_contains_str_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        emptyData,
                        emptyLength,
                        emptyByteCount,
                        emptyHash
                    )),
                    1
                )
            }
        }
    }

    // STDLIB-TEXT-FN-012: kk_string_contains_ignoreCase_flat
    //
    // Asserts the raw Boolean scalar returned by `kk_string_contains_ignoreCase_flat`
    // matches Kotlin's `CharSequence.contains(other, ignoreCase)` semantics:
    // - empty needle always matches (mirroring `String.contains("")`)
    // - case-sensitive mode (`ignoreCase = false`) behaves like `kk_string_contains_str_flat`
    // - case-insensitive mode matches across mixed-case ASCII without copying
    //   into a normalized scratch buffer.
    func testStringContainsIgnoreCase() {
        func contains(_ source: String, _ other: String, ignoreCase: Int) -> Int {
            withFlatString(source) { data, length, byteCount, hash in
                withFlatString(other) { otherData, otherLength, otherByteCount, otherHash in
                    kk_unbox_bool(kk_string_contains_ignoreCase_flat(
                        data,
                        length,
                        byteCount,
                        hash,
                        otherData,
                        otherLength,
                        otherByteCount,
                        otherHash,
                        ignoreCase
                    ))
                }
            }
        }

        // ignoreCase = false: identical to kk_string_contains_str_flat.
        XCTAssertEqual(
            contains("HelloWorld", "World", ignoreCase: 0),
            1,
            "case-sensitive hit should return raw `true`"
        )
        XCTAssertEqual(
            contains("HelloWorld", "world", ignoreCase: 0),
            0,
            "case-sensitive miss should return raw `false`"
        )
        XCTAssertEqual(
            contains("HelloWorld", "", ignoreCase: 0),
            1,
            "empty needle should always match"
        )

        // ignoreCase = true: case-insensitive substring match.
        XCTAssertEqual(
            contains("HelloWorld", "world", ignoreCase: 1),
            1,
            "case-insensitive hit should return raw `true`"
        )
        XCTAssertEqual(
            contains("HelloWorld", "WORLD", ignoreCase: 1),
            1,
            "fully uppercased needle should return raw `true` when ignoreCase=true"
        )
        XCTAssertEqual(
            contains("HelloWorld", "", ignoreCase: 1),
            1,
            "empty needle should always match even when ignoreCase=true"
        )

        // Needle longer than source must return false without indexing OOB.
        XCTAssertEqual(
            contains("hi", "there", ignoreCase: 1),
            0
        )

        // Truly absent needle returns false even with ignoreCase=true.
        XCTAssertEqual(
            contains("HelloWorld", "zzz", ignoreCase: 1),
            0
        )
    }

    func testStringToIntSuccessAndFailure() {
        var thrown = 0
        withFlatString("42") { data, length, byteCount, hash in
            let value = kk_string_toInt_flat(data, length, byteCount, hash, &thrown)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(value, 42)
        }

        withFlatString("4x") { data, length, byteCount, hash in
            _ = kk_string_toInt_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("NumberFormatException"))
    }

    func testStringToIntRadixThrowsOnInvalidRadix() {
        var thrown = 0

        withFlatString("10") { data, length, byteCount, hash in
            _ = kk_string_toInt_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToIntOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ff") { data, length, byteCount, hash in
            XCTAssertEqual(kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown), 255)
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
    }

    func testStringToIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToUByteOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ff") { data, length, byteCount, hash in
            XCTAssertEqual(kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown), 255)
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("100") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
    }

    func testStringToUByteOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToUShortOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ffff") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                Int(UInt16.max)
            )
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("10000") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
    }

    func testStringToUShortOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToUIntOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ffffffff") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                Int(UInt32.max)
            )
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("100000000") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
    }

    func testStringToUIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToULongOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ffffffffffffffff") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
            )
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("10000000000000000") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            XCTAssertEqual(
                kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown),
                runtimeNullSentinelInt
            )
            XCTAssertEqual(thrown, 0)
        }
    }

    func testStringToULongOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToDoubleParsesSpecialValuesAndThrowsOnInvalidInput() {
        var thrown = 0
        let parsed = withFlatString("  -Infinity ") { data, length, byteCount, hash in
            kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertEqual(thrown, 0)
        let parsedValue = Double(bitPattern: UInt64(bitPattern: Int64(parsed)))
        XCTAssertEqual(parsedValue, -.infinity)

        let nanRaw = withFlatString("NaN") { data, length, byteCount, hash in
            kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertEqual(thrown, 0)
        let nanValue = Double(bitPattern: UInt64(bitPattern: Int64(nanRaw)))
        XCTAssertTrue(nanValue.isNaN)

        withFlatString("nope") { data, length, byteCount, hash in
            _ = kk_string_toDouble_flat(data, length, byteCount, hash, &thrown)
        }
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("NumberFormatException"))
    }

    func testStringFormatSupportsStringIntAndDoubleSpecifiers() {
        let args = makeRuntimeArray([
            rawFromRuntimeString("age"),
            7,
            Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern)),
        ])

        let formatted = flatStringReturnValueNoThrow("%s:%d %.2f", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "age:7 3.50")
    }

    func testStringFormatSupportsFloatingSpecifiersForIntegersAndBoxedFloats() {
        let args = makeRuntimeArray([
            3,
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
        ])

        let formatted = flatStringReturnValueNoThrow("%.1f %.1f %.1f", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "3.0 1.5 2.5")
    }

    func testStringFormatSupportsPositionalArguments() {
        let args = makeRuntimeArray([
            7,
            rawFromRuntimeString("age"),
        ])

        let formatted = flatStringReturnValueNoThrow("%2$s:%1$d", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "age:7")
    }

    func testStringFormatSupportsBooleanSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_bool(1),
            kk_box_bool(0),
            runtimeNullSentinelInt,
        ])

        let formatted = flatStringReturnValueNoThrow("%b %B %b", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "true FALSE false")
    }

    func testStringFormatPreservesSixtyFourBitIntegerWidth() {
        let signed = Int(Int64.max)
        let unsigned = Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
        let args = makeRuntimeArray([signed, unsigned])

        let formatted = flatStringReturnValueNoThrow("%d %x", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "9223372036854775807 ffffffffffffffff")
    }

    func testStringFormatSupportsBoxedIntegerSpecifiers() {
        let boxedSigned = kk_box_long(Int(Int64.max))
        let boxedUnsigned = kk_box_long(Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
        let args = makeRuntimeArray([boxedSigned, boxedUnsigned])

        let formatted = flatStringReturnValueNoThrow("%d %x", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "9223372036854775807 ffffffffffffffff")
    }

    func testStringFormatSupportsBoxedScalarStringSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_long(Int(Int64.max)),
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
            kk_box_char(Int(Character("A").unicodeScalars.first?.value ?? 0)),
            kk_box_bool(1),
        ])

        let formatted = flatStringReturnValueNoThrow("%s %s %s %s %s", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "9223372036854775807 1.5 2.5 A true")
    }

    func testStringFormatSupportsEscapedPercentWithoutArguments() {
        let formatted = flatStringReturnValueNoThrow("progress=100%%", intArg: kk_array_new(0), using: kk_string_format_flat)
        XCTAssertEqual(formatted, "progress=100%")
    }

    func testStringFormatTreatsUnsupportedUnsignedConversionAsLiteral() {
        let args = makeRuntimeArray([7])
        let formatted = flatStringReturnValueNoThrow("%u", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "%u")
    }

    func testStringFormatTreatsUnsupportedGroupingFlagsAsLiteral() {
        let args = makeRuntimeArray([1234])
        let formatted = flatStringReturnValueNoThrow("%,d", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "%,d")
    }

    func testStringFormatSupportsScientificNotationForDouble() {
        let args = makeRuntimeArray([kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 1234.5.bitPattern)))])
        let formatted = flatStringReturnValueNoThrow("%.2e", intArg: args, using: kk_string_format_flat)
        XCTAssertEqual(formatted, "1.23e+03")
    }

    func testStringFormatLocaleUsesLocaleDecimalSeparator() {
        let locale = makeLocale(language: "de", country: "DE")
        let args = makeRuntimeArray([
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern))),
        ])
        let formatted = flatStringReturnValue(
            "%.1f",
            leadingIntArg: locale,
            trailingIntArg: args,
            using: kk_string_format_locale_flat
        )
        XCTAssertEqual(formatted, "3,5")
    }

    func testStringFormatNullLocaleKeepsNonLocalizedFormatting() {
        let args = makeRuntimeArray([
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern))),
        ])
        let formatted = flatStringReturnValue(
            "%.1f",
            leadingIntArg: runtimeNullSentinelInt,
            trailingIntArg: args,
            using: kk_string_format_locale_flat
        )
        XCTAssertEqual(formatted, "3.5")
    }

    // MARK: - kk_throwable_new

    func testThrowableNewCreatesThrowable() {
        let msg = makeRuntimeString("error occurred")
        let throwable = kk_throwable_new(msg)
        XCTAssertNotNil(throwable)
        let output = capturePrintln { kk_println_any(throwable) }
        XCTAssertTrue(output.contains("error occurred"))
    }

    func testThrowableNewWithNilUsesDefaultMessage() {
        let throwable = kk_throwable_new(nil)
        XCTAssertNotNil(throwable)
        let output = capturePrintln { kk_println_any(throwable) }
        XCTAssertTrue(output.contains("Throwable"))
    }

    func testThrowableIsCancellationReturnsFalseForNil() {
        XCTAssertEqual(kk_throwable_is_cancellation(0), 0)
    }

    func testThrowableIsCancellationReturnsFalseForRegularThrowable() {
        let throwable = kk_throwable_new(makeRuntimeString("not cancellation"))
        let raw = Int(bitPattern: throwable)
        XCTAssertEqual(kk_throwable_is_cancellation(raw), 0)
    }

    func testThrowableAddSuppressedPreservesInsertionOrder() {
        let primary = Int(bitPattern: kk_throwable_new(makeRuntimeString("primary")))
        let suppressed1 = Int(bitPattern: kk_throwable_new(makeRuntimeString("suppressed1")))
        let suppressed2 = Int(bitPattern: kk_throwable_new(makeRuntimeString("suppressed2")))

        _ = kk_throwable_addSuppressed(primary, suppressed1)
        _ = kk_throwable_addSuppressed(primary, suppressed2)

        let suppressed = kk_throwable_getSuppressed(primary)
        XCTAssertEqual(kk_array_size(suppressed), 2)

        var thrown = 0
        XCTAssertEqual(kk_array_get(suppressed, 0, &thrown), suppressed1)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_array_get(suppressed, 1, &thrown), suppressed2)
        XCTAssertEqual(thrown, 0)
    }

    func testThrowableAddSuppressedRejectsSelfSuppression() {
        let primary = Int(bitPattern: kk_throwable_new(makeRuntimeString("primary")))

        _ = kk_throwable_addSuppressed(primary, primary)

        let suppressed = kk_throwable_getSuppressed(primary)
        XCTAssertEqual(kk_array_size(suppressed), 0)
    }

    func testThrowableAddSuppressedIgnoresNullAndInvalidHandles() {
        let primary = Int(bitPattern: kk_throwable_new(makeRuntimeString("primary")))

        _ = kk_throwable_addSuppressed(primary, runtimeNullSentinelInt)
        _ = kk_throwable_addSuppressed(primary, 0)
        _ = kk_throwable_addSuppressed(primary, 123456789)
        _ = kk_throwable_addSuppressed(runtimeNullSentinelInt, primary)
        _ = kk_throwable_addSuppressed(123456789, primary)

        let suppressed = kk_throwable_getSuppressed(primary)
        XCTAssertEqual(kk_array_size(suppressed), 0)
    }

    func testThrowableSuppressedExceptionsReturnsList() {
        let primary = Int(bitPattern: kk_throwable_new(makeRuntimeString("primary")))
        let suppressed1 = Int(bitPattern: kk_throwable_new(makeRuntimeString("suppressed1")))
        let suppressed2 = Int(bitPattern: kk_throwable_new(makeRuntimeString("suppressed2")))

        _ = kk_throwable_addSuppressed(primary, suppressed1)
        _ = kk_throwable_addSuppressed(primary, suppressed2)

        let suppressed = kk_throwable_suppressedExceptions(primary)
        XCTAssertEqual(kk_list_size(suppressed), 2)
        XCTAssertEqual(kk_list_get(suppressed, 0), suppressed1)
        XCTAssertEqual(kk_list_get(suppressed, 1), suppressed2)
    }

    func testThrowablePrintStackTraceWritesRenderedMessageToStandardError() {
        let throwable = Int(bitPattern: kk_throwable_new(makeRuntimeString("print me")))

        let output = captureStandardError {
            XCTAssertEqual(kk_throwable_printStackTrace(throwable), 0)
        }

        XCTAssertEqual(output, "print me")
    }

    // MARK: - kk_array_new

    func testArrayNewCreatesArray() {
        let array = kk_array_new(5)
        XCTAssertNotEqual(array, 0)
    }

    func testArrayNewZeroLengthCreatesEmptyArray() {
        let array = kk_array_new(0)
        XCTAssertNotEqual(array, 0)
    }

    func testArrayOfNullsCreatesNullableSlots() {
        let array = kk_array_of_nulls(3)
        XCTAssertNotEqual(array, 0)
        XCTAssertEqual(kk_array_size(array), 3)

        var thrown = 0
        XCTAssertEqual(kk_array_get(array, 0, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_array_get(array, 1, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_array_get(array, 2, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    // MARK: - kk_array_get / kk_array_set

    func testArraySetAndGetMultipleIndices() {
        let array = kk_array_new(3)
        var thrown = 0
        _ = kk_array_set(array, 0, 10, &thrown)
        XCTAssertEqual(thrown, 0)
        _ = kk_array_set(array, 1, 20, &thrown)
        XCTAssertEqual(thrown, 0)
        _ = kk_array_set(array, 2, 30, &thrown)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(kk_array_get(array, 0, &thrown), 10)
        XCTAssertEqual(kk_array_get(array, 1, &thrown), 20)
        XCTAssertEqual(kk_array_get(array, 2, &thrown), 30)
    }

    func testArrayGetOutOfBoundsNegativeIndex() {
        let array = kk_array_new(2)
        var thrown = 0
        _ = kk_array_get(array, -1, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testArraySetOutOfBoundsThrows() {
        let array = kk_array_new(2)
        var thrown = 0
        _ = kk_array_set(array, 5, 99, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testArrayGetNullArrayThrows() {
        var thrown = 0
        _ = kk_array_get(0, 0, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    func testArraySetNullArrayThrows() {
        var thrown = 0
        _ = kk_array_set(0, 0, 42, &thrown)
        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - kk_vararg_spread_concat

    func testVarargSpreadConcatSingleElements() {
        // pairs: [0, 10, 0, 20] means two scalar elements (marker=0)
        let pairs = kk_array_new(4)
        var thrown = 0
        _ = kk_array_set(pairs, 0, 0, &thrown) // marker: scalar
        _ = kk_array_set(pairs, 1, 10, &thrown) // value: 10
        _ = kk_array_set(pairs, 2, 0, &thrown) // marker: scalar
        _ = kk_array_set(pairs, 3, 20, &thrown) // value: 20

        let result = kk_vararg_spread_concat(pairs, 2)
        XCTAssertNotEqual(result, 0)

        XCTAssertEqual(kk_array_get(result, 0, &thrown), 10)
        XCTAssertEqual(kk_array_get(result, 1, &thrown), 20)
    }

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
        XCTAssertEqual(kk_array_get(result, 0, &thrown), 100)
        XCTAssertEqual(kk_array_get(result, 1, &thrown), 200)
        XCTAssertEqual(kk_array_get(result, 2, &thrown), 300)
    }

    func testVarargSpreadConcatEmptyPairsReturnsEmptyArray() {
        let result = kk_vararg_spread_concat(0, 0)
        // pairCount is 0, should return empty array
        XCTAssertNotEqual(result, 0)
    }

    // MARK: - kk_println_any with boxed values

    func testPrintlnBoxedInt() {
        let boxed = kk_box_int(42)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        XCTAssertEqual(output, "42")
    }

    func testPrintlnBoxedBoolTrue() {
        let boxed = kk_box_bool(1)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        XCTAssertEqual(output, "true")
    }

    func testPrintlnBoxedBoolFalse() {
        let boxed = kk_box_bool(0)
        let ptr = UnsafeMutableRawPointer(bitPattern: boxed)
        let output = capturePrintln { kk_println_any(ptr) }
        XCTAssertEqual(output, "false")
    }

    func testPrintlnBoxedString() {
        let str = makeRuntimeString("hello world")
        let output = capturePrintln { kk_println_any(str) }
        XCTAssertEqual(output, "hello world")
    }

    func testPrintlnThrowable() {
        let msg = makeRuntimeString("some error")
        let throwable = kk_throwable_new(msg)
        let output = capturePrintln { kk_println_any(throwable) }
        XCTAssertTrue(output.contains("some error"))
    }

    // MARK: - STDLIB-TEXT-FN-115: String.withIndex()

    func testStringWithIndexReturnsListOfIndexedValues() {
        let resultRaw = withFlatString("abc") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        XCTAssertNotNil(list, "withIndex should return a list")
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testStringWithIndexElementsAreIndexedValuePairs() {
        let resultRaw = withFlatString("ab") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        XCTAssertNotNil(list)

        let elements = list?.elements ?? []
        XCTAssertEqual(elements.count, 2)

        // First element: IndexedValue(index=0, value='a')
        XCTAssertEqual(kk_pair_first(elements[0]), 0)
        XCTAssertEqual(kk_unbox_char(kk_pair_second(elements[0])), 97) // 'a'

        // Second element: IndexedValue(index=1, value='b')
        XCTAssertEqual(kk_pair_first(elements[1]), 1)
        XCTAssertEqual(kk_unbox_char(kk_pair_second(elements[1])), 98) // 'b'
    }

    func testStringWithIndexEmptyStringReturnsEmptyList() {
        let resultRaw = withFlatString("") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testStringWithIndexNonASCIICharsGetCorrectIndices() {
        let resultRaw = withFlatString("aé🐻") { data, length, byteCount, hash in
            kk_string_withIndex_flat(data, length, byteCount, hash)
        }
        let list = runtimeListBox(from: resultRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 4)

        let expectedIndices = [0, 1, 2, 3]
        let expectedCodeUnits = [97, 233, 0xD83D, 0xDC3B] // 'a', 'é', high surrogate, low surrogate
        for (i, elem) in (list?.elements ?? []).enumerated() {
            XCTAssertEqual(kk_pair_first(elem), expectedIndices[i], "Index mismatch at \(i)")
            XCTAssertEqual(kk_unbox_char(kk_pair_second(elem)), expectedCodeUnits[i], "Code unit mismatch at \(i)")
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

    private func makeRuntimeArray(_ values: [Int]) -> Int {
        let array = kk_array_new(values.count)
        var thrown = 0
        for (index, value) in values.enumerated() {
            _ = kk_array_set(array, index, value, &thrown)
            XCTAssertEqual(thrown, 0)
        }
        return array
    }

    private func assertFindAnyOfPair(
        _ pairRaw: Int,
        offset: Int,
        match: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertNotEqual(pairRaw, runtimeNullSentinelInt, file: file, line: line)
        guard pairRaw != runtimeNullSentinelInt,
              let pairPtr = UnsafeMutableRawPointer(bitPattern: pairRaw),
              let pairBox = tryCast(pairPtr, to: RuntimePairBox.self)
        else {
            XCTFail("Expected RuntimePairBox result", file: file, line: line)
            return
        }
        XCTAssertEqual(pairBox.firstValue.tag, RuntimeValue.rawTag, file: file, line: line)
        XCTAssertEqual(pairBox.firstValue.payload0, offset, file: file, line: line)
        XCTAssertEqual(pairBox.secondValue.tag, RuntimeValue.stringTag, file: file, line: line)
        XCTAssertEqual(runtimeRenderAnyForPrint(pairBox.secondValue), match, file: file, line: line)
        XCTAssertEqual(kk_pair_first(pairRaw), offset, file: file, line: line)
        XCTAssertEqual(
            runtimeStringFromRawOrPanic(kk_pair_second(pairRaw), caller: #function),
            match,
            file: file,
            line: line
        )
    }

    private func assertStringValueList(
        _ list: RuntimeListBox?,
        equals expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let list else {
            XCTFail("Expected a RuntimeListBox", file: file, line: line)
            return
        }
        XCTAssertEqual(
            list.values.map(\.tag),
            Array(repeating: RuntimeValue.stringTag, count: expected.count),
            file: file,
            line: line
        )
        XCTAssertEqual(list.elements.map(runtimeStringValue), expected, file: file, line: line)
    }

    private func assertStringValueSequence(
        _ sequenceRaw: Int,
        equals expected: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let sequence = runtimeSequenceBox(from: sequenceRaw) else {
            XCTFail("Expected a RuntimeSequenceBox", file: file, line: line)
            return
        }
        guard case let .valueSource(values)? = sequence.steps.first else {
            XCTFail("Expected aggregate RuntimeValue sequence source", file: file, line: line)
            return
        }
        XCTAssertEqual(
            values.map(\.tag),
            Array(repeating: RuntimeValue.stringTag, count: expected.count),
            file: file,
            line: line
        )
        XCTAssertEqual(runtimeSequenceSourceElements(from: sequenceRaw)?.map(runtimeStringValue), expected, file: file, line: line)
    }

    private func assertRawValueSequence(
        _ sequenceRaw: Int,
        equals expected: [Int],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let sequence = runtimeSequenceBox(from: sequenceRaw) else {
            XCTFail("Expected a RuntimeSequenceBox", file: file, line: line)
            return
        }
        guard case let .valueSource(values)? = sequence.steps.first else {
            XCTFail("Expected aggregate RuntimeValue sequence source", file: file, line: line)
            return
        }
        XCTAssertEqual(
            values.map(\.tag),
            Array(repeating: RuntimeValue.rawTag, count: expected.count),
            file: file,
            line: line
        )
        XCTAssertEqual(values.map(\.payload0), expected, file: file, line: line)
        XCTAssertEqual(runtimeSequenceSourceElements(from: sequenceRaw), expected, file: file, line: line)
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

    private func assertIndexedStringValue(
        _ raw: Int,
        index: Int,
        value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(runtimeObjectTypeID(rawValue: raw), indexedValueRuntimeTypeID, file: file, line: line)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let pairBox = tryCast(ptr, to: RuntimePairBox.self)
        else {
            XCTFail("Expected IndexedValue RuntimePairBox", file: file, line: line)
            return
        }

        XCTAssertEqual(pairBox.firstValue.tag, RuntimeValue.rawTag, file: file, line: line)
        XCTAssertEqual(pairBox.firstValue.payload0, index, file: file, line: line)
        XCTAssertEqual(pairBox.secondValue.tag, RuntimeValue.stringTag, file: file, line: line)
        XCTAssertEqual(runtimeRenderAnyForPrint(pairBox.secondValue), value, file: file, line: line)
        XCTAssertEqual(runtimeElementToString(raw), "IndexedValue(index=\(index), value=\(value))", file: file, line: line)
    }

    private func assertIndexedCharValue(
        _ raw: Int,
        index: Int,
        scalar: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(runtimeObjectTypeID(rawValue: raw), indexedValueRuntimeTypeID, file: file, line: line)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let pairBox = tryCast(ptr, to: RuntimePairBox.self)
        else {
            XCTFail("Expected IndexedValue RuntimePairBox", file: file, line: line)
            return
        }

        XCTAssertEqual(pairBox.firstValue.tag, RuntimeValue.rawTag, file: file, line: line)
        XCTAssertEqual(pairBox.firstValue.payload0, index, file: file, line: line)
        XCTAssertEqual(pairBox.secondValue.tag, RuntimeValue.charTag, file: file, line: line)
        XCTAssertEqual(pairBox.secondValue.payload0, scalar, file: file, line: line)
        XCTAssertEqual(kk_unbox_char(kk_pair_second(raw)), scalar, file: file, line: line)
    }

    private func assertStringPairValue(
        _ raw: Int,
        first: String,
        second: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let pairBox = tryCast(ptr, to: RuntimePairBox.self)
        else {
            XCTFail("Expected RuntimePairBox", file: file, line: line)
            return
        }

        XCTAssertEqual(pairBox.firstValue.tag, RuntimeValue.stringTag, file: file, line: line)
        XCTAssertEqual(pairBox.secondValue.tag, RuntimeValue.stringTag, file: file, line: line)
        XCTAssertEqual(runtimeRenderAnyForPrint(pairBox.firstValue), first, file: file, line: line)
        XCTAssertEqual(runtimeRenderAnyForPrint(pairBox.secondValue), second, file: file, line: line)
    }

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
