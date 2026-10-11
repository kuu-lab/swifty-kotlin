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
            let value = __kk_string_toInt_flat(data, length, byteCount, hash, &thrown)
            #expect(thrown == 0)
            #expect(value == 42)
        }

        withFlatString("4x") { data, length, byteCount, hash in
            _ = __kk_string_toInt_flat(data, length, byteCount, hash, &thrown)
        }
        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("NumberFormatException"))
    }

    @Test
    func testStringToIntRadixThrowsOnInvalidRadix() {
        var thrown = 0

        withFlatString("10") { data, length, byteCount, hash in
            _ = __kk_string_toInt_radix_flat(data, length, byteCount, hash, 1, &thrown)
        }

        #expect(thrown != 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        #expect(thrownOutput.contains("IllegalArgumentException"))
    }

    @Test
    func testStringToIntOrNullRadixSuccessAndInvalidInput() {
        var thrown = 0

        withFlatString("ff") { data, length, byteCount, hash in
            #expect(__kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(__kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            __kk_string_toIntOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
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
            #expect(__kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == 255)
            #expect(thrown == 0)
        }
        withFlatString("100") { data, length, byteCount, hash in
            #expect(__kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(__kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToUByteOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            __kk_string_toUByteOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
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
            #expect(__kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt16.max))
            #expect(thrown == 0)
        }
        withFlatString("10000") { data, length, byteCount, hash in
            #expect(__kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(__kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToUShortOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            __kk_string_toUShortOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
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
            #expect(__kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == Int(UInt32.max))
            #expect(thrown == 0)
        }
        withFlatString("100000000") { data, length, byteCount, hash in
            #expect(__kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(__kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToUIntOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            __kk_string_toUIntOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
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
            #expect(kk_unbox_ulong(__kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown)) == Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
            #expect(thrown == 0)
        }
        withFlatString("10000000000000000") { data, length, byteCount, hash in
            #expect(__kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
        withFlatString("xz") { data, length, byteCount, hash in
            #expect(__kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 16, &thrown) == runtimeNullSentinelInt)
            #expect(thrown == 0)
        }
    }

    @Test
    func testStringToULongOrNullRadixThrowsOnInvalidRadix() {
        var thrown = 0

        let result = withFlatString("10") { data, length, byteCount, hash in
            __kk_string_toULongOrNull_radix_flat(data, length, byteCount, hash, 1, &thrown)
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
        #expect(abs(doubleFromRuntimeBits(kk_unbox_double(parsed)) - 4.0) <= 1e-12)
    }

    @Test
    func testStringToFloatParsesKotlinFloatingLiteralsAndRejectsSwiftOnlySpellings() {
        var thrown = 0
        let cases: [(String, Float)] = [
            ("1.", 1.0),
            (".5", 0.5),
            ("1e3", 1_000.0),
            ("1.0d", 1.0),
            ("+6.25F", 6.25),
            ("0x1.8p1", 3.0),
        ]

        for (source, expected) in cases {
            thrown = 0
            let raw = __kk_string_toFloat(rawFromRuntimeString(source), &thrown)
            #expect(thrown == 0, "Expected \(source) to parse")
            #expect(abs(floatFromRuntimeBits(raw) - expected) <= 1e-6)
        }

        let specialCases: [(String, Float)] = [
            ("NaN", .nan),
            ("Infinity", .infinity),
            ("+Infinity", .infinity),
            ("-Infinity", -.infinity),
        ]
        for (source, expected) in specialCases {
            let raw = __kk_string_toFloatOrNull(rawFromRuntimeString(source))
            #expect(raw != runtimeNullSentinelInt, "Expected \(source) to parse")
            let parsed = floatFromRuntimeBits(kk_unbox_float(raw))
            if expected.isNaN {
                #expect(parsed.isNaN)
            } else {
                #expect(parsed == expected)
            }
        }

        for source in ["inf", "nan", "infinity", "-nan", "INFINITY"] {
            #expect(
                __kk_string_toFloatOrNull(rawFromRuntimeString(source)) == runtimeNullSentinelInt,
                "Expected \(source) to be rejected by toFloatOrNull"
            )

            thrown = 0
            _ = __kk_string_toFloat(rawFromRuntimeString(source), &thrown)
            #expect(thrown != 0, "Expected \(source) to be rejected by toFloat")
        }
    }

    private func expectFormatError(_ template: String, _ arguments: [Int], _ kind: String) {
        let args = makeRuntimeArray(arguments)
        for localized in [false, true] {
            var thrown = 0
            let result: String
            if localized {
                result = flatStringReturnValue(template, leadingIntArg: runtimeNullSentinelInt,
                    trailingIntArg: args, using: __kk_string_format_locale_flat, outThrown: &thrown)
            } else {
                result = flatStringReturnValue(template, intArg: args, using: __kk_string_format_flat, outThrown: &thrown)
            }
            #expect(result.isEmpty)
            let box = throwableBox(from: thrown)
            #expect(box?.exceptionFQName == "java.util.\(kind)", "\(template), localized=\(localized)")
            #expect(box?.exceptionHierarchyFQNames.contains("java.util.IllegalFormatException") == true)
            #expect(box?.exceptionHierarchyFQNames.contains("kotlin.IllegalArgumentException") == true)
        }
    }

    @Test
    func testStringFormatValidatesSpecifiersAndArguments() {
        let string = rawFromRuntimeString("s")
        expectFormatError("%.2x", [255], "IllegalFormatPrecisionException")
        expectFormatError("%d", [string], "IllegalFormatConversionException")
        expectFormatError("%s %s", [string], "MissingFormatArgumentException")
        expectFormatError("%+s", [string], "FormatFlagsConversionMismatchException")
        expectFormatError("%05s", [string], "FormatFlagsConversionMismatchException")
        expectFormatError("%c", [string], "IllegalFormatConversionException")
        expectFormatError("%.2d", [5], "IllegalFormatPrecisionException")
        expectFormatError("%8.3d", [5], "IllegalFormatPrecisionException")
        expectFormatError("%q", [5], "UnknownFormatConversionException")
        expectFormatError("%--5s", [string], "DuplicateFormatFlagsException")
        expectFormatError("%-s", [string], "MissingFormatWidthException")
        expectFormatError("%+ d", [1], "IllegalFormatFlagsException")
        expectFormatError("%f", [kk_box_int(1)], "IllegalFormatConversionException")
        expectFormatError("%d", [kk_box_double(Int(bitPattern: UInt(1.0.bitPattern)))], "IllegalFormatConversionException")
        expectFormatError("%tQ", [string], "IllegalFormatConversionException")
        expectFormatError("%c", [-1], "IllegalFormatCodePointException")
        expectFormatError("%c", [0x110000], "IllegalFormatCodePointException")
        expectFormatError("%i", [1], "UnknownFormatConversionException")
        expectFormatError("%.s", [string], "UnknownFormatConversionException")
        expectFormatError("%", [], "UnknownFormatConversionException")
        expectFormatError("%5n", [], "IllegalFormatWidthException")
        expectFormatError("%+%", [], "IllegalFormatFlagsException")
        expectFormatError("%s %q", [], "UnknownFormatConversionException")
        for template in ["%0s", "%0c", "%0tQ"] {
            expectFormatError(template, [1], "FormatFlagsConversionMismatchException")
        }
        expectFormatError("%0%", [], "IllegalFormatFlagsException")
        expectFormatError("%-.2d", [1], "MissingFormatWidthException")
        expectFormatError("%#s", [], "MissingFormatArgumentException")
        expectFormatError("%#s", [string], "FormatFlagsConversionMismatchException")
        expectFormatError("%100000sX%d", [string, string], "IllegalFormatConversionException")
        expectFormatError("%100000sX%s", [string], "MissingFormatArgumentException")
        let null = makeRuntimeArray([runtimeNullSentinelInt])
        #expect(flatStringReturnValue("%.2f", intArg: null, using: __kk_string_format_flat) == "nu")
    }

    @Test
    func testStringFormatNullAndBooleanPrecision() {
        let args = makeRuntimeArray([runtimeNullSentinelInt, kk_box_bool(1)])
        #expect(flatStringReturnValue("%1$.2f|%1$.2h|%1$.2b|%2$.2B",
            intArg: args, using: __kk_string_format_flat) == "nu|nu|fa|TR")
    }

    @Test
    func testStringFormatSupportsStringIntAndDoubleSpecifiers() {
        let args = makeRuntimeArray([
            rawFromRuntimeString("age"),
            7,
            Int(bitPattern: UInt(truncatingIfNeeded: 3.5.bitPattern)),
        ])

        let formatted = flatStringReturnValue("%s:%d %.2f", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "age:7 3.50")
    }

    @Test
    func testStringFormatUsesAggregateArgumentStorageWithoutLegacyStringBoxes() {
        let args = makeRuntimeValueArray([
            runtimeStringAggregateValue("age"),
            RuntimeValue(raw: 7),
            RuntimeValue(raw: kk_box_double(Int(bitPattern: UInt(3.5.bitPattern)))),
        ])
        let baselineObjectCount = kk_debugging_global_object_count()

        let formatted = flatStringReturnValue("%s:%d %.1f", intArg: args, using: __kk_string_format_flat)
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
    func testStringFormatSupportsLegacyRawFloatingValuesAndBoxedFloats() {
        let args = makeRuntimeArray([
            3,
            kk_box_float(Int(Float(1.5).bitPattern)),
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 2.5.bitPattern))),
        ])

        let formatted = flatStringReturnValue("%.1f %.1f %.1f", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "3.0 1.5 2.5")
    }

    @Test
    func testStringFormatFloatingRoundingMatchesJavaFormatter() {
        let boxDouble: (Double) -> Int = { value in
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: value.bitPattern)))
        }
        let args = makeRuntimeArray([
            boxDouble(1.005),
            boxDouble(0.25),
            boxDouble(0.35),
            boxDouble(0.5),
            boxDouble(2.5),
            boxDouble(2.675),
            boxDouble(1.0005),
        ])

        let formatted = flatStringReturnValue(
            "%.2f %.1f %.1f %.0f %.0f %.2f %.3f",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "1.01 0.3 0.4 1 3 2.68 1.001")
    }

    @Test
    func testStringFormatFloatingPrecisionUsesShortestDecimalRepresentation() {
        let boxDouble: (Double) -> Int = { value in
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: value.bitPattern)))
        }
        let args = makeRuntimeArray([
            boxDouble(0.1),
            boxDouble(0.1),
            boxDouble(1.005),
            boxDouble(0.0001),
            boxDouble(0.00001),
            boxDouble(999999.5),
        ])

        let formatted = flatStringReturnValue(
            "%.20f %.17g %.2e %.6g %.6g %.6g",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "0.10000000000000000000 0.10000000000000000 1.01e+00 0.000100000 1.00000e-05 1.00000e+06")
    }

    @Test
    func testStringFormatGeneralAndNonFiniteFloatsMatchJavaFormatter() {
        let boxDouble: (Double) -> Int = { value in
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: value.bitPattern)))
        }
        let args = makeRuntimeArray([
            boxDouble(0.0001234),
            boxDouble(.nan),
            boxDouble(.infinity),
            boxDouble(-.infinity),
            boxDouble(.nan),
        ])

        let formatted = flatStringReturnValue(
            "%g|%f|%.2f|%(f|%010E",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "0.000123400|NaN|Infinity|(Infinity)|       NAN")
    }

    @Test
    func testStringFormatParenthesizesNegativeDecimalValues() {
        let args = makeRuntimeArray([
            -5,
            -5,
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: (-1234.5).bitPattern))),
        ])

        let formatted = flatStringReturnValue(
            "%(d|%(05d|%(,.1f",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "(5)|(005)|(1,234.5)")
    }

    @Test
    func testStringFormatParenthesesPreserveNonNegativeValuesAndIntegerLimits() {
        let args = makeRuntimeArray([
            kk_box_int(-42),
            kk_box_int(42),
            kk_box_int(0),
            kk_box_int(Int(Int32.min)),
            kk_box_long_nonnull(Int(Int64.min)),
            kk_box_long(Int(Int64.max)),
        ])

        let formatted = flatStringReturnValue(
            "%(d|%(d|%(d|%(d|%(d|%(d",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "(42)|42|0|(2147483648)|(9223372036854775808)|9223372036854775807")
    }

    @Test
    func testStringFormatParenthesesCombineWithWidthSignsAndArgumentReuse() {
        let cases: [(String, Int, String)] = [
            ("%(6d", -42, "  (42)"),
            ("%-(6d", -42, "(42)  "),
            ("%(06d", -42, "(0042)"),
            ("%(3d", -42, "(42)"),
            ("%(06d", 42, "000042"),
            ("%+(06d", -42, "(0042)"),
            ("%+(06d", 42, "+00042"),
            ("% (06d", -42, "(0042)"),
            ("% (06d", 42, " 00042"),
            ("%(,012d", -1234, "(000001,234)"),
            ("%(,012d", 1234, "00000001,234"),
            ("%1$(d|%<(06d", -42, "(42)|(0042)"),
        ]
        for (template, value, expected) in cases {
            let formatted = flatStringReturnValue(
                template,
                intArg: makeRuntimeArray([kk_box_int(value)]),
                using: __kk_string_format_flat
            )
            #expect(formatted == expected, "Template: \(template), value: \(value)")
        }
    }

    @Test
    func testStringFormatParenthesesCoverFloatingPointSignsAndSpecialValues() {
        let cases: [(String, Double, String)] = [
            ("%(010.2f", -42.5, "(00042.50)"),
            ("%(010.2f", 42.5, "0000042.50"),
            ("%(010.2f", -0.0, "(00000.00)"),
            ("%(010.2f", 0.0, "0000000.00"),
            ("%(.2e", -42.5, "(4.25e+01)"),
            ("%(.2E", -42.5, "(4.25E+01)"),
            ("%(.4g", -42.5, "(42.50)"),
            ("%(012f", -.infinity, "  (Infinity)"),
            ("%(012E", -.infinity, "  (INFINITY)"),
            ("%(012f", .infinity, "    Infinity"),
            ("%(012f", .nan, "         NaN"),
        ]
        for (template, value, expected) in cases {
            let argument = kk_box_double_nonnull(Int(bitPattern: UInt(truncatingIfNeeded: value.bitPattern)))
            let formatted = flatStringReturnValue(
                template,
                intArg: makeRuntimeArray([argument]),
                using: __kk_string_format_flat
            )
            #expect(formatted == expected, "Template: \(template), value: \(value)")
        }
    }

    @Test
    func testStringFormatParenthesesApplyAfterLocaleGroupingBeforePadding() {
        let formatted = flatStringReturnValue(
            "%(,012d|%(,012.2f",
            leadingIntArg: makeLocale(language: "de", country: "DE"),
            trailingIntArg: makeRuntimeArray([
                kk_box_int(-1234),
                kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: (-1234.5).bitPattern))),
            ]),
            using: __kk_string_format_locale_flat
        )
        #expect(formatted == "(000001.234)|(001.234,50)")
    }

    @Test
    func testStringFormatSupportsJavaHexFloatingPoint() {
        let boxDouble: (Double) -> Int = { value in
            kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: value.bitPattern)))
        }
        let args = makeRuntimeArray([
            boxDouble(1.0),
            boxDouble(3.0),
            boxDouble(0.1),
            boxDouble(.leastNonzeroMagnitude),
            boxDouble(.leastNonzeroMagnitude),
            boxDouble(1.0),
        ])

        let formatted = flatStringReturnValue(
            "%a|%A|%.2a|%a|%.1a|%010a",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "0x1.0p0|0X1.8P1|0x1.9ap-4|0x0.0000000000001p-1022|0x1.0p-1074|0x0001.0p0")
    }

    @Test
    func testStringFormatSupportsPositionalArguments() {
        let args = makeRuntimeArray([
            7,
            rawFromRuntimeString("age"),
        ])

        let formatted = flatStringReturnValue("%2$s:%1$d", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "age:7")
    }

    @Test
    func testStringFormatSupportsPreviousArgumentReuseFlag() {
        func format(_ template: String, _ args: [Int]) -> String {
            flatStringReturnValue(template, intArg: makeRuntimeArray(args), using: __kk_string_format_flat)
        }

        // `java.util.Formatter` `<` flag: reuse the argument selected by the
        // previous specifier without consuming the ordinary index.
        #expect(format("%s %<s", [rawFromRuntimeString("x")]) == "x x")
        #expect(format("%d|%03d|%<d", [7, 8]) == "7|008|8")
        #expect(format("%1$s %<s", [rawFromRuntimeString("a")]) == "a a")
        #expect(format("%s %s %<s %<s", [
            rawFromRuntimeString("a"),
            rawFromRuntimeString("b"),
            rawFromRuntimeString("c"),
        ]) == "a b b b")
        #expect(format("%s %<s %s", [
            rawFromRuntimeString("a"),
            rawFromRuntimeString("b"),
        ]) == "a a b")
        #expect(format("%2$s %s %<s", [
            rawFromRuntimeString("a"),
            rawFromRuntimeString("b"),
            rawFromRuntimeString("c"),
        ]) == "b a a")
        #expect(format("%d %<05d %<d", [42]) == "42 00042 42")
        #expect(format("%s %<d", [7]) == "7 7")
        #expect(format("%s|%<5s|%-<5s", [rawFromRuntimeString("x")]) == "x|    x|x    ")

        // The `<` flag overrides an explicit `%n$` index, matching
        // `java.util.Formatter`.
        #expect(format("%s %2$<s", [
            rawFromRuntimeString("a"),
            rawFromRuntimeString("b"),
        ]) == "a a")

        expectFormatError("%<s", [rawFromRuntimeString("x")], "MissingFormatArgumentException")
    }

    @Test
    func testStringFormatSupportsBooleanSpecifiers() {
        let args = makeRuntimeArray([
            kk_box_bool(1),
            kk_box_bool(0),
            runtimeNullSentinelInt,
        ])

        let formatted = flatStringReturnValue("%b %B %b", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "true FALSE false")
    }

    @Test
    func testStringFormatBooleanSpecifierUsesJavaTruthinessForNonBooleans() {
        let args = makeRuntimeValueArray([
            runtimeStringAggregateValue(""),
            RuntimeValue(raw: 0),
            RuntimeValue(raw: 1),
            RuntimeValue(raw: kk_box_bool(0)),
            RuntimeValue(raw: kk_box_bool(1)),
            RuntimeValue(raw: runtimeNullSentinelInt),
        ])

        let formatted = flatStringReturnValue(
            "%b %b %b %b %b %b",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "true true true false true false")
    }

    @Test
    func testStringFormatStringPrecisionUsesUTF16CodeUnits() {
        func format(_ template: String, _ argument: String) -> String {
            let args = makeRuntimeArray([rawFromRuntimeString(argument)])
            return flatStringReturnValue(template, intArg: args, using: __kk_string_format_flat)
        }

        // U+10000 (𐀀) is one grapheme / two UTF-16 units. Precision 3 keeps the
        // high surrogate; precision 2 stops before the pair; precision 4 keeps it.
        let supplementary = "ab\u{10000}cd"
        #expect(runtimeKotlinStringUTF16CodeUnits(format("%.3s", supplementary)) == [0x61, 0x62, 0xD800])
        #expect(runtimeKotlinStringUTF16CodeUnits(format("%.2s", supplementary)) == [0x61, 0x62])
        #expect(runtimeKotlinStringUTF16CodeUnits(format("%.4s", supplementary)) == [0x61, 0x62, 0xD800, 0xDC00])

        // NFD "é" is two UTF-16 units (e + combining acute). Precision 3 is e, ◌́, a.
        let combining = "e\u{0301}abc"
        #expect(runtimeKotlinStringUTF16CodeUnits(format("%.3s", combining)) == [0x65, 0x0301, 0x61])
        #expect(runtimeKotlinStringUTF16CodeUnits(format("%.1s", combining)) == [0x65])

        #expect(format("%.3s", "hello") == "hel")
        #expect(format("%.0s", "hello") == "")
        #expect(format("%.10s", "hi") == "hi")
        #expect(format("%.2S", "abcd") == "AB")
    }

    @Test
    func testStringFormatPreservesSixtyFourBitIntegerWidth() {
        let signed = Int(Int64.max)
        let unsigned = Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max))
        let args = makeRuntimeArray([signed, unsigned])

        let formatted = flatStringReturnValue("%d %x", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "9223372036854775807 ffffffffffffffff")
    }

    @Test
    func testStringFormatSupportsBoxedIntegerSpecifiers() {
        let boxedSigned = kk_box_long(Int(Int64.max))
        let boxedUnsigned = kk_box_long(Int(bitPattern: UInt(truncatingIfNeeded: UInt64.max)))
        let args = makeRuntimeArray([boxedSigned, boxedUnsigned])

        let formatted = flatStringReturnValue("%d %x", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "9223372036854775807 ffffffffffffffff")
    }

    @Test
    func testStringFormatUsesKotlinIntegerWidthsForHexAndOctal() {
        let args = makeRuntimeArray([
            kk_box_int(-1),
            kk_box_long(-1),
            kk_box_int(-1),
            kk_box_int(-8),
            kk_box_long(-8),
        ])

        let formatted = flatStringReturnValue(
            "%x %x %X %o %o",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(
            formatted ==
                "ffffffff ffffffffffffffff FFFFFFFF 37777777770 1777777777777777777770"
        )
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

        let formatted = flatStringReturnValue("%s %s %s %s %s", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "9223372036854775807 1.5 2.5 A true")
    }

    @Test
    func testStringFormatSupportsEscapedPercentWithoutArguments() {
        let formatted = flatStringReturnValue("progress=100%%", intArg: kk_array_new(0), using: __kk_string_format_flat)
        #expect(formatted == "progress=100%")
    }

    @Test
    func testStringFormatRejectsUnsupportedUnsignedConversion() {
        expectFormatError("%u", [7], "UnknownFormatConversionException")
    }

    @Test
    func testStringFormatGroupsIntegersForGroupingFlag() {
        let args = makeRuntimeArray([1234567])
        let formatted = flatStringReturnValue("%,d", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "1,234,567")
    }

    @Test
    func testStringFormatZeroPadsGroupedIntegersAfterGrouping() {
        let args = makeRuntimeArray([1234])
        let formatted = flatStringReturnValue("%,012d", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "00000001,234")
    }

    @Test
    func testStringFormatSupportsScientificNotationForDouble() {
        let args = makeRuntimeArray([kk_box_double(Int(bitPattern: UInt(truncatingIfNeeded: 1234.5.bitPattern)))])
        let formatted = flatStringReturnValue("%.2e", intArg: args, using: __kk_string_format_flat)
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

    @Test
    func testStringFormatRejectsIntMaxPrecisionWithoutTrap() {
        expectFormatError("%.9223372036854775807f", [], "IllegalFormatPrecisionException")
        expectFormatError("%.99999999999999999999f", [], "IllegalFormatPrecisionException")
    }

    @Test
    func testStringFormatRejectsLargeWidthWithoutAllocationFailure() {
        expectFormatError("%9223372036854775807d", [], "IllegalFormatWidthException")
        expectFormatError("%100001d", [], "IllegalFormatWidthException")
    }

    @Test
    func testStringFormatEnforcesCumulativeBudgetAcrossMultipleSpecifiers() {
        let str = rawFromRuntimeString("x")
        let args = makeRuntimeArray([str, str])
        let formatted = flatStringReturnValue("%60000s%60000s", intArg: args, using: __kk_string_format_flat)
        #expect(formatted.count <= 100_000)
        #expect(formatted.count == 60_000)
    }

    @Test
    func testStringFormatExactBoundaryHandling() {
        let str = rawFromRuntimeString("x")
        let args1 = makeRuntimeArray([str])
        let formattedWidthBoundary = flatStringReturnValue("%100000s", intArg: args1, using: __kk_string_format_flat)
        #expect(formattedWidthBoundary.count == 100_000)
        #expect(formattedWidthBoundary.hasSuffix("x"))

        let args2 = makeRuntimeArray([str, str])
        let formattedBudgetBoundary = flatStringReturnValue("%50000s%50000s", intArg: args2, using: __kk_string_format_flat)
        #expect(formattedBudgetBoundary.count == 100_000)
    }

    @Test
    func testStringFormatSupportsHexHashCodeConversion() {
        let args = makeRuntimeArray([
            rawFromRuntimeString("abc"),
            runtimeNullSentinelInt,
            42,
        ])
        let formatted = flatStringReturnValue(
            "%1$h %2$h %3$h %1$H %1$8h",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "17862 null 2a 17862    17862")
    }

    @Test
    func testStringFormatSupportsDateTimeEpochConversions() {
        let millis = 1_700_000_000_123
        let args = makeRuntimeArray([millis, runtimeNullSentinelInt])
        let formatted = flatStringReturnValue(
            "%1$tQ %1$ts %2$tQ",
            intArg: args,
            using: __kk_string_format_flat
        )
        #expect(formatted == "1700000000123 1700000000 null")
    }

    @Test
    func testStringFormatDateTimeUsesLocalCalendarFields() {
        let millis: Int64 = 1_704_067_200_000
        let date = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let args = makeRuntimeArray([Int(millis)])
        let formatted = flatStringReturnValue(
            "%1$tY %1$tm %1$td %1$tF",
            intArg: args,
            using: __kk_string_format_flat
        )
        let expected = String(format: "%04d %02d %02d %04d-%02d-%02d", year, month, day, year, month, day)
        #expect(formatted == expected)
    }

    @Test
    func testStringFormatDateTimeSupportsInstantBox() {
        let millis = 1_700_000_000_123
        let instant = kk_instant_from_epoch_millis(millis)
        let args = makeRuntimeArray([instant])
        let formatted = flatStringReturnValue("%1$tQ %1$ts", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "1700000000123 1700000000")
    }

    @Test
    func testStringFormatMixedStringAndHashConversions() {
        let args = makeRuntimeArray([42, 42])
        let formatted = flatStringReturnValue("%s %h", intArg: args, using: __kk_string_format_flat)
        #expect(formatted == "42 2a")
    }

    private func doubleFromRuntimeBits(_ raw: Int) -> Double {
        Double(bitPattern: UInt64(bitPattern: Int64(raw)))
    }

    private func floatFromRuntimeBits(_ raw: Int) -> Float {
        Float(bitPattern: UInt32(truncatingIfNeeded: UInt(bitPattern: raw)))
    }
}
#endif
