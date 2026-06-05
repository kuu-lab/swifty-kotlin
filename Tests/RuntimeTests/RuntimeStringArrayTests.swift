@testable import Runtime
import XCTest

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private typealias RuntimeStringUnaryEntry = @convention(c) (Int, Int, UnsafeMutablePointer<Int>?) -> Int

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

    private func flatStringValue(
        data: UnsafePointer<UInt8>?,
        length: Int,
        byteCount: Int,
        hash: Int
    ) -> String {
        runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
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

    // MARK: - kk_string_concat

    func testStringConcatTwoStrings() {
        let firstStr = makeRuntimeString("Hello, ")
        let secondStr = makeRuntimeString("World!")
        let result = kk_string_concat(firstStr, secondStr)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "Hello, World!")
    }

    func testStringConcatWithNilLeftReturnsRightOnly() {
        let rightStr = makeRuntimeString("World")
        let result = kk_string_concat(nil, rightStr)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "World")
    }

    func testStringConcatWithNilRightReturnsLeftOnly() {
        let leftStr = makeRuntimeString("Hello")
        let result = kk_string_concat(leftStr, nil)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "Hello")
    }

    func testStringConcatBothNilReturnsEmptyString() {
        let result = kk_string_concat(nil, nil)
        let output = capturePrintln { kk_println_any(result) }
        XCTAssertEqual(output, "")
    }

    // MARK: - kk_string_compareTo

    func testStringCompareToEqual() {
        let firstStr = makeRuntimeString("abc")
        let secondStr = makeRuntimeString("abc")
        XCTAssertEqual(kk_string_compareTo(firstStr, secondStr), 0)
    }

    func testStringCompareToLessThan() {
        let firstStr = makeRuntimeString("abc")
        let secondStr = makeRuntimeString("xyz")
        XCTAssertEqual(kk_string_compareTo(firstStr, secondStr), -1)
    }

    func testStringCompareToGreaterThan() {
        let firstStr = makeRuntimeString("xyz")
        let secondStr = makeRuntimeString("abc")
        XCTAssertEqual(kk_string_compareTo(firstStr, secondStr), 1)
    }

    func testStringCompareToNils() {
        // Both nil -> equal empty strings
        XCTAssertEqual(kk_string_compareTo(nil, nil), 0)
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

    func testStringTrimRemovesLeadingAndTrailingWhitespace() {
        let raw = kk_string_trim(rawFromRuntimeString("  hello  "))
        XCTAssertEqual(runtimeStringValue(raw), "hello")
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
        }
        withFlatString("  \n\t") { data, length, byteCount, hash in
            XCTAssertEqual(kk_unbox_bool(kk_string_isBlank_flat(data, length, byteCount, hash)), 1)
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
                kk_unbox_bool(kk_string_equalsIgnoreCase_flat(data, length, byteCount, hash, nil, 0, 0, 0, 1)),
                0
            )
            withFlatString("kswiftk") { otherData, otherLength, otherByteCount, otherHash in
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
        }
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
            XCTAssertEqual(kk_unbox_char(kk_string_first_flat(data, length, byteCount, hash, &thrown)), 97)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_unbox_char(kk_string_last_flat(data, length, byteCount, hash, &thrown)), 99)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_unbox_char(kk_string_firstOrNull_flat(data, length, byteCount, hash)), 97)
            XCTAssertEqual(kk_unbox_char(kk_string_lastOrNull_flat(data, length, byteCount, hash)), 99)
            XCTAssertEqual(kk_unbox_char(kk_string_getOrNull_flat(data, length, byteCount, hash, 1)), 98)
            XCTAssertEqual(kk_string_getOrNull_flat(data, length, byteCount, hash, -1), runtimeNullSentinelInt)
            XCTAssertEqual(kk_string_getOrNull_flat(data, length, byteCount, hash, 3), runtimeNullSentinelInt)

            thrown = 0
            XCTAssertEqual(kk_string_single_flat(data, length, byteCount, hash, &thrown), 0)
            XCTAssertNotEqual(thrown, 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            XCTAssertTrue(thrownOutput.contains("more than one element"))
            XCTAssertEqual(kk_string_singleOrNull_flat(data, length, byteCount, hash), runtimeNullSentinelInt)
        }

        withFlatString("x") { data, length, byteCount, hash in
            var thrown = 0
            XCTAssertEqual(kk_unbox_char(kk_string_single_flat(data, length, byteCount, hash, &thrown)), 120)
            XCTAssertEqual(thrown, 0)
            XCTAssertEqual(kk_unbox_char(kk_string_singleOrNull_flat(data, length, byteCount, hash)), 120)
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
        let splitRaw = kk_string_split(
            rawFromRuntimeString("1,2,3"),
            rawFromRuntimeString(",")
        )
        let list = runtimeListBox(from: splitRaw)
        XCTAssertEqual(list?.elements.count, 3)
        XCTAssertEqual(list?.elements.map(runtimeStringValue), ["1", "2", "3"])
    }



    func testStringToListAndToCharArrayReturnCharElements() {
        let listRaw = kk_string_toList(rawFromRuntimeString("abc"))
        let charArrayRaw = kk_string_toCharArray(rawFromRuntimeString("abc"))

        let list = runtimeListBox(from: listRaw)
        let charArray = runtimeArrayBox(from: charArrayRaw)
        XCTAssertNotNil(list)
        XCTAssertNotNil(charArray)
        let expected = [97, 98, 99]
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
        XCTAssertEqual(charArray?.elements.map(kk_unbox_char), expected)
    }

    // MARK: - STDLIB-TEXT-FN-109: String.toTypedArray()

    func testStringToTypedArrayReturnsBoxedArrayOfChar() {
        let arrayRaw = kk_string_toTypedArray(rawFromRuntimeString("abc"))
        let array = runtimeArrayBox(from: arrayRaw)
        XCTAssertNotNil(array, "toTypedArray should return a RuntimeArrayBox")
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        XCTAssertEqual(array?.elements.count, 3)
        XCTAssertEqual(array?.elements.map(kk_unbox_char), expected)
    }

    func testStringToTypedArrayEmptyStringReturnsEmptyArray() {
        let arrayRaw = kk_string_toTypedArray(rawFromRuntimeString(""))
        let array = runtimeArrayBox(from: arrayRaw)
        XCTAssertNotNil(array, "toTypedArray on empty string should return a RuntimeArrayBox")
        XCTAssertEqual(array?.elements.count, 0)
    }

    func testStringToTypedArrayIsDistinctFromToCharArray() {
        let strRaw = rawFromRuntimeString("hi")
        let typedArrayRaw = kk_string_toTypedArray(strRaw)
        let charArrayRaw = kk_string_toCharArray(strRaw)
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

    // MARK: - STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)

    func testStringToCollectionAppendsCharsToMutableList() {
        let strRaw = rawFromRuntimeString("abc")
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        let returnedRaw = kk_string_toCollection(strRaw, destRaw)

        XCTAssertEqual(returnedRaw, destRaw, "toCollection should return the destination collection")
        let list = runtimeListBox(from: returnedRaw)
        XCTAssertNotNil(list)
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringToCollectionPreservesExistingElements() {
        let strRaw = rawFromRuntimeString("de")
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: [kk_box_char(97)]))
        _ = kk_string_toCollection(strRaw, destRaw)

        let list = runtimeListBox(from: destRaw)
        let expected = [97, 100, 101] // 'a', 'd', 'e'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringToCollectionEmptyStringLeavesDestinationUnchanged() {
        let strRaw = rawFromRuntimeString("")
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        _ = kk_string_toCollection(strRaw, destRaw)

        let list = runtimeListBox(from: destRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testStringToCollectionWithNonASCII() {
        let strRaw = rawFromRuntimeString("aé")
        let destRaw = registerRuntimeObject(RuntimeListBox(elements: []))
        _ = kk_string_toCollection(strRaw, destRaw)

        let list = runtimeListBox(from: destRaw)
        let expected = [97, 233] // 'a', 'é'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    // MARK: - STDLIB-TEXT-FN-108: kk_string_toSortedSet tests

    func testStringToSortedSetReturnsSortedUniqueChars() {
        // "cba" should produce {a, b, c} sorted ascending
        let setRaw = kk_string_toSortedSet(rawFromRuntimeString("cba"))
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.elements.map(kk_unbox_char), [97, 98, 99]) // a, b, c
    }

    func testStringToSortedSetDeduplicates() {
        // "aabba" — unique chars are 'a'(97) and 'b'(98) in ascending order
        let setRaw = kk_string_toSortedSet(rawFromRuntimeString("aabba"))
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.elements.map(kk_unbox_char), [97, 98]) // a, b
    }

    func testStringToSortedSetEmptyString() {
        let setRaw = kk_string_toSortedSet(rawFromRuntimeString(""))
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.elements.count, 0)
    }

    func testStringToSortedSetSingleChar() {
        let setRaw = kk_string_toSortedSet(rawFromRuntimeString("z"))
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
        XCTAssertEqual(setBox?.elements.map(kk_unbox_char), [122]) // 'z'
    }

    func testStringToSortedSetUsesUTF16CodeUnits() {
        let setRaw = kk_string_toSortedSet(rawFromRuntimeString("a🐻a"))
        let setBox = runtimeSetBox(from: setRaw)
        XCTAssertNotNil(setBox)
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
            let sortedSet = runtimeSetBox(from: kk_string_toSortedSet_flat(data, length, byteCount, hash))
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
        let strRaw = rawFromRuntimeString("abc")
        let iterableRaw = kk_string_asIterable(strRaw)

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
        }
    }

    func testStringAsIterableToListMaterialises() {
        let strRaw = rawFromRuntimeString("abc")
        let iterableRaw = kk_string_asIterable(strRaw)
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        XCTAssertNotNil(list)
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringAsIterableIteratorYieldsCharacters() {
        let strRaw = rawFromRuntimeString("hi")
        let iterableRaw = kk_string_asIterable(strRaw)
        let iterRaw = kk_string_iterable_iterator(iterableRaw)

        XCTAssertEqual(kk_string_iterator_hasNext(iterRaw), 1)
        let first = kk_unbox_char(kk_string_iterator_next(iterRaw))
        XCTAssertEqual(first, 104) // 'h'

        XCTAssertEqual(kk_string_iterator_hasNext(iterRaw), 1)
        let second = kk_unbox_char(kk_string_iterator_next(iterRaw))
        XCTAssertEqual(second, 105) // 'i'

        XCTAssertEqual(kk_string_iterator_hasNext(iterRaw), 0)
    }

    func testStringAsIterableWithNonASCII() {
        let strRaw = rawFromRuntimeString("aé🐻")
        let iterableRaw = kk_string_asIterable(strRaw)
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        let expectedScalars: [Int] = [97, 233, 128_059] // 'a', 'é', '🐻'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expectedScalars)
    }

    func testStringAsIterableEmptyString() {
        let strRaw = rawFromRuntimeString("")
        let iterableRaw = kk_string_asIterable(strRaw)
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testStringAsIterablePrintDoesNotMaterialiseList() {
        let strRaw = rawFromRuntimeString("aé🐻")
        let iterableRaw = kk_string_asIterable(strRaw)
        let baselineObjectCount = kk_runtime_heap_object_count()

        let output = capturePrintln {
            kk_println_any(UnsafeMutableRawPointer(bitPattern: iterableRaw))
        }

        XCTAssertEqual(output, "[a, é, 🐻]")
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    func testStringAsIterableRenderDoesNotMaterialiseList() {
        let strRaw = rawFromRuntimeString("abc")
        let iterableRaw = kk_string_asIterable(strRaw)
        let baselineObjectCount = kk_runtime_heap_object_count()

        XCTAssertEqual(runtimeRenderAnyForPrint(iterableRaw), "[a, b, c]")
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    func testStringFunctionsWithNonASCII() {
        let text = "aé🐻"
        let listRaw = kk_string_toList(rawFromRuntimeString(text))
        let list = runtimeListBox(from: listRaw)
        let expectedScalars: [Int] = [97, 233, 128_059] // 'a', 'é', '🐻'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expectedScalars)

        XCTAssertEqual(runtimeStringValue(kk_string_take(rawFromRuntimeString(text), 2, nil)), "aé")
        XCTAssertEqual(runtimeStringValue(kk_string_drop(rawFromRuntimeString(text), 1, nil)), "é🐻")
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
        XCTAssertEqual(runtimeStringValue(kk_string_take(rawFromRuntimeString("abcde"), 0, nil)), "")
        XCTAssertEqual(runtimeStringValue(kk_string_take(rawFromRuntimeString("abcde"), 2, nil)), "ab")
        XCTAssertEqual(runtimeStringValue(kk_string_take(rawFromRuntimeString("abcde"), 10, nil)), "abcde")
        XCTAssertEqual(runtimeStringValue(kk_string_drop(rawFromRuntimeString("abcde"), 0, nil)), "abcde")
        XCTAssertEqual(runtimeStringValue(kk_string_drop(rawFromRuntimeString("abcde"), 2, nil)), "cde")
        XCTAssertEqual(runtimeStringValue(kk_string_drop(rawFromRuntimeString("abcde"), 10, nil)), "")
    }

    func testStringTakeNegativeThrowsIllegalArgumentException() {
        // STDLIB-005-BUG-01: negative count must throw, not silently return empty/full.
        var thrown = 0
        _ = kk_string_take(rawFromRuntimeString("hello"), -1, &thrown)
        XCTAssertNotEqual(thrown, 0, "kk_string_take(-1) should set outThrown")

        var thrown2 = 0
        _ = kk_string_drop(rawFromRuntimeString("hello"), -1, &thrown2)
        XCTAssertNotEqual(thrown2, 0, "kk_string_drop(-1) should set outThrown")
    }

    func testStringTakeLastDropLastFunctions() {
        XCTAssertEqual(runtimeStringValue(kk_string_takeLast(rawFromRuntimeString("abcde"), 0, nil)), "")
        XCTAssertEqual(runtimeStringValue(kk_string_takeLast(rawFromRuntimeString("abcde"), 2, nil)), "de")
        XCTAssertEqual(runtimeStringValue(kk_string_takeLast(rawFromRuntimeString("abcde"), 10, nil)), "abcde")
        XCTAssertEqual(runtimeStringValue(kk_string_dropLast(rawFromRuntimeString("abcde"), 0, nil)), "abcde")
        XCTAssertEqual(runtimeStringValue(kk_string_dropLast(rawFromRuntimeString("abcde"), 2, nil)), "abc")
        XCTAssertEqual(runtimeStringValue(kk_string_dropLast(rawFromRuntimeString("abcde"), 10, nil)), "")
    }

    func testStringTakeLastDropLastNegativeThrowsIllegalArgumentException() {
        // STDLIB-005-BUG-01: negative count must throw, not silently return empty/full.
        var thrown = 0
        _ = kk_string_takeLast(rawFromRuntimeString("hello"), -1, &thrown)
        XCTAssertNotEqual(thrown, 0, "kk_string_takeLast(-1) should set outThrown")

        var thrown2 = 0
        _ = kk_string_dropLast(rawFromRuntimeString("hello"), -1, &thrown2)
        XCTAssertNotEqual(thrown2, 0, "kk_string_dropLast(-1) should set outThrown")
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
        let replaced = kk_string_replace(
            rawFromRuntimeString("aba"),
            rawFromRuntimeString("a"),
            rawFromRuntimeString("z")
        )
        XCTAssertEqual(runtimeStringValue(replaced), "zbz")
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
        let replaced = kk_string_replaceFirstChar(
            rawFromRuntimeString("abc"),
            unsafeBitCast(runtimeReplaceFirstCharWithUppercaseB, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(runtimeStringValue(replaced), "Bbc")
    }

    func testStringReplaceFirstCharFallsBackToOriginalScalarForInvalidReplacement() {
        let original = "éclair"
        let replaced = kk_string_replaceFirstChar(
            rawFromRuntimeString(original),
            unsafeBitCast(runtimeReplaceFirstCharWithInvalidScalar, to: Int.self),
            0,
            nil
        )

        XCTAssertEqual(runtimeStringValue(replaced), original)
    }

    func testStringReplaceFirstCharPropagatesThrownValue() {
        var thrown = -1
        let replaced = kk_string_replaceFirstChar(
            rawFromRuntimeString("abc"),
            unsafeBitCast(runtimeReplaceFirstCharThrowing, to: Int.self),
            0,
            &thrown
        )

        XCTAssertEqual(runtimeStringValue(replaced), "")
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("replaceFirstChar failure"))
    }

    func testStringStartsWithEndsWithContains() {
        let source = rawFromRuntimeString("HelloWorld")
        XCTAssertEqual(kk_unbox_bool(kk_string_startsWith(source, rawFromRuntimeString("Hello"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_endsWith(source, rawFromRuntimeString("World"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_contains_str(source, rawFromRuntimeString("World"))), 1)
        XCTAssertEqual(kk_unbox_bool(kk_string_contains_str(source, rawFromRuntimeString(""))), 1)
    }

    // STDLIB-TEXT-FN-012: kk_string_contains_ignoreCase
    //
    // Asserts the boxed Boolean returned by `kk_string_contains_ignoreCase`
    // matches Kotlin's `CharSequence.contains(other, ignoreCase)` semantics:
    // - empty needle always matches (mirroring `String.contains("")`)
    // - case-sensitive mode (`ignoreCase = false`) behaves like `kk_string_contains_str`
    // - case-insensitive mode matches across mixed-case ASCII without copying
    //   into a normalized scratch buffer.
    func testStringContainsIgnoreCase() {
        let source = rawFromRuntimeString("HelloWorld")

        // ignoreCase = false → identical to kk_string_contains_str
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(source, rawFromRuntimeString("World"), 0)),
            1,
            "case-sensitive hit should box `true`"
        )
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(source, rawFromRuntimeString("world"), 0)),
            0,
            "case-sensitive miss should box `false`"
        )
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(source, rawFromRuntimeString(""), 0)),
            1,
            "empty needle should always match"
        )

        // ignoreCase = true → case-insensitive substring match
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(source, rawFromRuntimeString("world"), 1)),
            1,
            "case-insensitive hit should box `true`"
        )
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(source, rawFromRuntimeString("WORLD"), 1)),
            1,
            "fully uppercased needle should box `true` when ignoreCase=true"
        )
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(source, rawFromRuntimeString(""), 1)),
            1,
            "empty needle should always match even when ignoreCase=true"
        )

        // Needle longer than source must return false without indexing OOB.
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(
                rawFromRuntimeString("hi"),
                rawFromRuntimeString("there"),
                1
            )),
            0
        )

        // Truly absent needle returns false even with ignoreCase=true.
        XCTAssertEqual(
            kk_unbox_bool(kk_string_contains_ignoreCase(source, rawFromRuntimeString("zzz"), 1)),
            0
        )
    }

    func testStringToIntSuccessAndFailure() {
        var thrown = 0
        let value = kk_string_toInt(rawFromRuntimeString("42"), &thrown)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(value, 42)

        _ = kk_string_toInt(rawFromRuntimeString("4x"), &thrown)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("NumberFormatException"))
    }

    func testStringToIntRadixThrowsOnInvalidRadix() {
        var thrown = 0

        _ = kk_string_toInt_radix(rawFromRuntimeString("10"), 1, &thrown)

        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToIntOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        XCTAssertEqual(kk_string_toIntOrNull_radix(rawFromRuntimeString("ff"), 16, &thrown), 255)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toIntOrNull_radix(rawFromRuntimeString("xz"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    func testStringToIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = kk_string_toIntOrNull_radix(rawFromRuntimeString("10"), 1, &thrown)

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToUByteOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        XCTAssertEqual(kk_string_toUByteOrNull_radix(rawFromRuntimeString("ff"), 16, &thrown), 255)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toUByteOrNull_radix(rawFromRuntimeString("100"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toUByteOrNull_radix(rawFromRuntimeString("xz"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    func testStringToUByteOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = kk_string_toUByteOrNull_radix(rawFromRuntimeString("10"), 1, &thrown)

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToUShortOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        XCTAssertEqual(kk_string_toUShortOrNull_radix(rawFromRuntimeString("ffff"), 16, &thrown), Int(UInt16.max))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toUShortOrNull_radix(rawFromRuntimeString("10000"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toUShortOrNull_radix(rawFromRuntimeString("xz"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    func testStringToUShortOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = kk_string_toUShortOrNull_radix(rawFromRuntimeString("10"), 1, &thrown)

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToUIntOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        XCTAssertEqual(kk_string_toUIntOrNull_radix(rawFromRuntimeString("ffffffff"), 16, &thrown), Int(UInt32.max))
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toUIntOrNull_radix(rawFromRuntimeString("100000000"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toUIntOrNull_radix(rawFromRuntimeString("xz"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    func testStringToUIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = kk_string_toUIntOrNull_radix(rawFromRuntimeString("10"), 1, &thrown)

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToULongOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        XCTAssertEqual(
            kk_string_toULongOrNull_radix(rawFromRuntimeString("ffffffffffffffff"), 16, &thrown),
            Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
        )
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toULongOrNull_radix(rawFromRuntimeString("10000000000000000"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(kk_string_toULongOrNull_radix(rawFromRuntimeString("xz"), 16, &thrown), runtimeNullSentinelInt)
        XCTAssertEqual(thrown, 0)
    }

    func testStringToULongOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = kk_string_toULongOrNull_radix(rawFromRuntimeString("10"), 1, &thrown)

        XCTAssertEqual(result, runtimeNullSentinelInt)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("IllegalArgumentException"))
    }

    func testStringToDoubleParsesSpecialValuesAndThrowsOnInvalidInput() {
        var thrown = 0
        let parsed = kk_string_toDouble(rawFromRuntimeString("  -Infinity "), &thrown)
        XCTAssertEqual(thrown, 0)
        let parsedValue = Double(bitPattern: UInt64(bitPattern: Int64(parsed)))
        XCTAssertEqual(parsedValue, -.infinity)

        let nanRaw = kk_string_toDouble(rawFromRuntimeString("NaN"), &thrown)
        XCTAssertEqual(thrown, 0)
        let nanValue = Double(bitPattern: UInt64(bitPattern: Int64(nanRaw)))
        XCTAssertTrue(nanValue.isNaN)

        _ = kk_string_toDouble(rawFromRuntimeString("nope"), &thrown)
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

        let formatted = kk_string_format(rawFromRuntimeString("%s:%d %.2f"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "age:7 3.50")
    }

    func testStringFormatSupportsFloatingSpecifiersForIntegersAndBoxedFloats() {
        let args = makeRuntimeArray([
            3,
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%.1f %.1f %.1f"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "3.0 1.5 2.5")
    }

    func testStringFormatSupportsPositionalArguments() {
        let args = makeRuntimeArray([
            7,
            rawFromRuntimeString("age"),
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%2$s:%1$d"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "age:7")
    }

    func testStringFormatSupportsBooleanSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_bool(1),
            kk_box_bool(0),
            runtimeNullSentinelInt,
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%b %B %b"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "true FALSE false")
    }

    func testStringFormatPreservesSixtyFourBitIntegerWidth() {
        let signed = Int(Int64.max)
        let unsigned = Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
        let args = makeRuntimeArray([signed, unsigned])

        let formatted = kk_string_format(rawFromRuntimeString("%d %x"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "9223372036854775807 ffffffffffffffff")
    }

    func testStringFormatSupportsBoxedIntegerSpecifiers() {
        let boxedSigned = kk_box_long(Int(Int64.max))
        let boxedUnsigned = kk_box_long(Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
        let args = makeRuntimeArray([boxedSigned, boxedUnsigned])

        let formatted = kk_string_format(rawFromRuntimeString("%d %x"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "9223372036854775807 ffffffffffffffff")
    }

    func testStringFormatSupportsBoxedScalarStringSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_long(Int(Int64.max)),
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
            kk_box_char(Int(Character("A").unicodeScalars.first?.value ?? 0)),
            kk_box_bool(1),
        ])

        let formatted = kk_string_format(rawFromRuntimeString("%s %s %s %s %s"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "9223372036854775807 1.5 2.5 A true")
    }

    func testStringFormatSupportsEscapedPercentWithoutArguments() {
        let formatted = kk_string_format(rawFromRuntimeString("progress=100%%"), kk_array_new(0))
        XCTAssertEqual(runtimeStringValue(formatted), "progress=100%")
    }

    func testStringFormatTreatsUnsupportedUnsignedConversionAsLiteral() {
        let args = makeRuntimeArray([7])
        let formatted = kk_string_format(rawFromRuntimeString("%u"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "%u")
    }

    func testStringFormatTreatsUnsupportedGroupingFlagsAsLiteral() {
        let args = makeRuntimeArray([1234])
        let formatted = kk_string_format(rawFromRuntimeString("%,d"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "%,d")
    }

    func testStringFormatSupportsScientificNotationForDouble() {
        let args = makeRuntimeArray([kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 1234.5.bitPattern)))])
        let formatted = kk_string_format(rawFromRuntimeString("%.2e"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "1.23e+03")
    }

    func testStringFormatLocaleUsesLocaleDecimalSeparator() {
        let locale = kk_locale_new_language_country(rawFromRuntimeString("de"), rawFromRuntimeString("DE"))
        let args = makeRuntimeArray([
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern))),
        ])
        let formatted = kk_string_format_locale(locale, rawFromRuntimeString("%.1f"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "3,5")
    }

    func testStringFormatNullLocaleKeepsNonLocalizedFormatting() {
        let args = makeRuntimeArray([
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern))),
        ])
        let formatted = kk_string_format_locale(runtimeNullSentinelInt, rawFromRuntimeString("%.1f"), args)
        XCTAssertEqual(runtimeStringValue(formatted), "3.5")
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
        let strRaw = rawFromRuntimeString("abc")
        let resultRaw = kk_string_withIndex(strRaw)
        let list = runtimeListBox(from: resultRaw)
        XCTAssertNotNil(list, "withIndex should return a list")
        XCTAssertEqual(list?.elements.count, 3)
    }

    func testStringWithIndexElementsAreIndexedValuePairs() {
        let strRaw = rawFromRuntimeString("ab")
        let resultRaw = kk_string_withIndex(strRaw)
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
        let strRaw = rawFromRuntimeString("")
        let resultRaw = kk_string_withIndex(strRaw)
        let list = runtimeListBox(from: resultRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 0)
    }

    func testStringWithIndexNonASCIICharsGetCorrectIndices() {
        let strRaw = rawFromRuntimeString("aé🐻")
        let resultRaw = kk_string_withIndex(strRaw)
        let list = runtimeListBox(from: resultRaw)
        XCTAssertNotNil(list)
        XCTAssertEqual(list?.elements.count, 4)

        let expectedIndices = [0, 1, 2, 3]
        let expectedScalars = [97, 233, 0xD83D, 0xDC3B] // 'a', 'é', high surrogate, low surrogate
        for (i, elem) in (list?.elements ?? []).enumerated() {
            XCTAssertEqual(kk_pair_first(elem), expectedIndices[i], "Index mismatch at \(i)")
            XCTAssertEqual(kk_unbox_char(kk_pair_second(elem)), expectedScalars[i], "Scalar mismatch at \(i)")
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

    private func runtimeStringValue(_ raw: Int) -> String {
        extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) ?? ""
    }
}
