#if canImport(Testing)
@testable import Runtime
import Testing
import Foundation

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

extension RuntimeStringArrayTests {
    // MARK: - STDLIB-006 string runtime ABI

    // trim/trimStart/trimEnd (whitespace and predicate variants),
    // isEmpty/isNotEmpty/isBlank/isNotBlank/isNullOrEmpty/isNullOrBlank,
    // orEmpty, getOrNull, and toBoolean* flat bridges are bundled Kotlin
    // source; their direct tests were removed. Coverage now lives in
    // Scripts/diff_cases via diff_kotlinc.sh.

    @Test
    func testFlatStringCaseConversionReturnsFlattenedStringFields() {
        #expect(flatStringReturnValue("KSwiftK", using: kk_string_lowercase_flat) == "kswiftk")
        #expect(flatStringReturnValue("KSwiftK", using: kk_string_uppercase_flat) == "KSWIFTK")
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
        }
    }

    @Test
    func testFlatStringNullableScalarRuntimeAPIsUseDataNull() {
        #expect(kk_unbox_bool(__kk_string_equals_flat(nil, 0, 0, 0, nil, 0, 0, 0)) == 1)

        withFlatString("") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(__kk_string_equals_flat(data, length, byteCount, hash, nil, 0, 0, 0)) == 0)
        }

        withFlatString("KSwiftK") { data, length, byteCount, hash in
            #expect(kk_unbox_bool(__kk_string_equals_flat(data, length, byteCount, hash, nil, 0, 0, 0)) == 0)
            withFlatString("kswiftk") { otherData, otherLength, otherByteCount, otherHash in
                #expect(kk_unbox_bool(
                        __kk_string_equals_flat(
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
                        __kk_string_equals_flat(
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
    func testFlatStringParseScalarRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("42") { data, length, byteCount, hash in
            var thrown = 0
            #expect(__kk_string_toInt_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(__kk_string_toLong_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(__kk_string_toShort_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(__kk_string_toByte_flat(data, length, byteCount, hash, &thrown) == 42)
            #expect(thrown == 0)
            #expect(__kk_string_toIntOrNull_flat(data, length, byteCount, hash) == 42)
            #expect(kk_unbox_long(__kk_string_toLongOrNull_flat(data, length, byteCount, hash)) == 42)
            #expect(__kk_string_toShortOrNull_flat(data, length, byteCount, hash) == 42)
            #expect(__kk_string_toByteOrNull_flat(data, length, byteCount, hash) == 42)
        }

        withFlatString("ff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(__kk_string_toInt_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
            #expect(__kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
            #expect(__kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
            #expect(__kk_string_toByte_radix_flat(data, length, byteCount, hash, 16, &thrown) == 0)
            #expect(thrown != 0)
        }

        withFlatString("ffff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(__kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt16.max))
            #expect(thrown == 0)
        }

        withFlatString("ffffffff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(__kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt32.max))
            #expect(thrown == 0)
        }

        withFlatString("ffffffffffffffff") { data, length, byteCount, hash in
            var thrown = 0
            #expect(kk_unbox_ulong(__kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown)) == Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
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
            #expect(__kk_string_toInt_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            #expect(thrownOutput.contains("NumberFormatException"))
            #expect(__kk_string_toIntOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(__kk_string_toDoubleOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(__kk_string_toFloatOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
        }
    }

    @Test
    func testFlatStringCharSelectionRuntimeAPIsUseFlattenedStringFields() {
        withFlatString("abc") { data, length, byteCount, hash in
            var thrown = 0
            #expect(__kk_string_first_flat(data, length, byteCount, hash, &thrown) == 97)
            #expect(thrown == 0)
            #expect(__kk_string_last_flat(data, length, byteCount, hash, &thrown) == 99)
            #expect(thrown == 0)
            #expect(__kk_string_firstOrNull_flat(data, length, byteCount, hash) == 97)
            #expect(__kk_string_lastOrNull_flat(data, length, byteCount, hash) == 99)
            #expect(__kk_string_get_flat(data, length, byteCount, hash, 1, &thrown) == 98)
            #expect(thrown == 0)

            thrown = 0
            #expect(__kk_string_get_flat(data, length, byteCount, hash, 3, &thrown) == 0)
            #expect(thrown != 0)

            thrown = 0
            #expect(__kk_string_single_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
            #expect(thrownOutput.contains("more than one element"))
            #expect(__kk_string_singleOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
        }

        withFlatString("x") { data, length, byteCount, hash in
            var thrown = 0
            #expect(__kk_string_single_flat(data, length, byteCount, hash, &thrown) == 120)
            #expect(thrown == 0)
            #expect(__kk_string_singleOrNull_flat(data, length, byteCount, hash) == 120)
        }

        withFlatString("") { data, length, byteCount, hash in
            var thrown = 0
            #expect(__kk_string_first_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            thrown = 0
            #expect(__kk_string_last_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            thrown = 0
            #expect(__kk_string_single_flat(data, length, byteCount, hash, &thrown) == 0)
            #expect(thrown != 0)
            #expect(__kk_string_firstOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(__kk_string_lastOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
            #expect(__kk_string_singleOrNull_flat(data, length, byteCount, hash) == runtimeNullSentinelInt)
        }
    }

    @Test
    func testStringGetOrNullUsesUTF16CodeUnits() {
        let expectedCodeUnits = Array("🥦".utf16)
        let stringRaw = registerRuntimeObject(RuntimeStringBox("🥦"))

        #expect(kk_unbox_char(kk_string_getOrNull(stringRaw, 0)) == Int(expectedCodeUnits[0]))
        #expect(kk_unbox_char(kk_string_getOrNull(stringRaw, 1)) == Int(expectedCodeUnits[1]))
        #expect(kk_string_getOrNull(stringRaw, 2) == runtimeNullSentinelInt)
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
        #expect(list?.elements.map(runtimeTestStringValue) == ["1", "2", "3"])
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
        let identity = "kotlin.Array@\(String(UInt32(truncatingIfNeeded: kk_any_hashCode(arrayRaw, 0)), radix: 16))"
        #expect(runtimeElementToString(arrayRaw) == identity)
        #expect(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: arrayRaw)) } == identity)
    }

    @Test
    func testThrowableStringConversionMatchesPrintln() {
        // Regression test: runtimeElementToString (used by kk_any_to_string, which
        // string template interpolation and the `+` concatenation operator lower to)
        // used to be missing a RuntimeThrowableBox case and fell through to printing
        // the raw pointer bit pattern instead of the Throwable rendering.
        // JDK-rooted exceptions keep their `java.lang.` prefix, matching kotlinc.
        let throwableRaw = runtimeAllocateIllegalStateException(message: "boom")
        let expected = "java.lang.IllegalStateException: boom"

        #expect(runtimeElementToString(throwableRaw) == expected)
        #expect(runtimeRenderAnyForPrint(throwableRaw) == expected)
        #expect(capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: throwableRaw)) } == expected)

        // anyFallbackTag() emits tag 1 ("default"/object) for class-typed operands
        // of `+`/string templates, so this exercises the exact ABI path the compiler
        // lowers `"$e"` and `"foo: " + e` to.
        let converted = kk_any_to_string(throwableRaw, 1)
        #expect(extractString(from: converted) ?? "" == expected)
    }

    @Test
    func testInstantAssertionMessageUsesIsoRepresentation() {
        let instantRaw = kk_instant_from_epoch_seconds(1, 500_000_000)
        let expected = "1970-01-01T00:00:01.500Z"

        #expect(runtimeRenderAnyForPrint(instantRaw) == expected)

        let assertionRaw = kk_assertion_error_new_message(instantRaw)
        let assertion = throwableBox(from: assertionRaw)
        #expect(assertion?.message == expected)
    }

    // KSP-405: take/drop are bundled Kotlin source (StringTakeDrop.kt);
    // their runtime bridges and direct tests were removed.
    // KSP-1394: repeat is bundled Kotlin source (StringBasics.kt); its
    // runtime bridge and direct tests were removed.

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
}
#endif
