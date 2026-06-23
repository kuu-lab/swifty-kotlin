@testable import Runtime
import XCTest

#if canImport(Glibc)
    import Glibc
#elseif canImport(Darwin)
    import Darwin
#endif

private func throwableBox(from handle: Int) -> RuntimeThrowableBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: handle) else {
        return nil
    }
    return tryCast(ptr, to: RuntimeThrowableBox.self)
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

    private func doubleFromRuntimeBits(_ raw: Int) -> Double {
        Double(bitPattern: UInt64(bitPattern: Int64(raw)))
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

    // MARK: - Compare / Format

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

    // MARK: - STDLIB-TEXT-FN-109: String.toTypedArray()

    // MARK: - STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)

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

    // MARK: - STDLIB-TEXT-FN-108: kk_string_toSortedSet tests

    // MARK: - STDLIB-317: String.asIterable() tests

    func testStringAsIterableReturnsLazyBox() {
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("abc"))

        // The iterable should be a RuntimeStringIterableBox, not a list.
        let iterableBox = runtimeStringIterableBox(from: iterableRaw)
        XCTAssertNotNil(iterableBox, "asIterable should return a RuntimeStringIterableBox")
        XCTAssertEqual(iterableBox?.source, "abc", "Box should store the immutable string payload")

        // It should NOT be a list (lazy, not materialised).
        let listBox = runtimeListBox(from: iterableRaw)
        XCTAssertNil(listBox, "asIterable should NOT materialise a list eagerly")
    }

    func testStringAsIterableToListMaterialises() {
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("abc"))
        let listRaw = kk_string_iterable_toList(iterableRaw)

        let list = runtimeListBox(from: listRaw)
        XCTAssertNotNil(list)
        let expected = [97, 98, 99] // 'a', 'b', 'c'
        XCTAssertEqual(list?.elements.map(kk_unbox_char), expected)
    }

    func testStringAsIterableIteratorYieldsCharacters() {
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("hi"))
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
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("hi"))
        let iterRaw = kk_string_iterable_iterator(iterableRaw)

        XCTAssertEqual(kk_string_iterator_next(iterRaw), 104)
        XCTAssertEqual(kk_string_iterator_next(iterRaw), 105)
        XCTAssertEqual(kk_string_iterator_next(iterRaw), 0)
    }

    func testStringAsIterableWithNonASCII() {
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("aé🐻"))
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
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("aba"))

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
        let listRaw = kk_iterable_toMutableList(kk_string_asIterable(rawFromRuntimeString("aba")))

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
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("aé🐻"))
        let result = kk_iterable_joinToString(
            iterableRaw,
            rawFromRuntimeString("|"),
            rawFromRuntimeString("<"),
            rawFromRuntimeString(">")
        )

        XCTAssertEqual(runtimeStringValue(Int(bitPattern: result)), "<a|é|?|?>")
    }

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

        XCTAssertEqual(runtimeStringValue(resultRaw), "<red|green|blue>")
        XCTAssertEqual(
            kk_debugging_global_object_count(),
            baselineObjectCount + 1,
            "kk_string_joinToString must not materialize RuntimeStringBox values from aggregate list storage"
        )
    }

    func testStringAsIterableAsSequencePreservesTaggedSourceValues() {
        let sequenceRaw = kk_iterable_asSequence(kk_string_asIterable(rawFromRuntimeString("ab")))
        let sequence = runtimeSequenceBox(from: sequenceRaw)

        guard case let .valueSource(values)? = sequence?.steps.first else {
            XCTFail("Expected String.asIterable().asSequence() to use RuntimeValue source storage")
            return
        }

        XCTAssertEqual(values.map(\.tag), [RuntimeValue.charTag, RuntimeValue.charTag])
        XCTAssertEqual(values.map(\.legacyRawValue), [97, 98])
    }

    func testStringAsIterableEmptyString() {
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString(""))
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
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("aé🐻"))
        let baselineObjectCount = kk_runtime_heap_object_count()

        let output = capturePrintln {
            kk_println_any(UnsafeMutableRawPointer(bitPattern: iterableRaw))
        }

        XCTAssertEqual(output, "[a, é, 🐻]")
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    func testStringAsIterableRenderDoesNotMaterialiseList() {
        let iterableRaw = kk_string_asIterable(rawFromRuntimeString("abc"))
        let baselineObjectCount = kk_runtime_heap_object_count()

        XCTAssertEqual(runtimeRenderAnyForPrint(iterableRaw), "[a, b, c]")
        XCTAssertEqual(kk_runtime_heap_object_count(), baselineObjectCount)
    }

    func testStringScalarIndexedOperationsWithNonASCII() {
        let textRaw = rawFromRuntimeString("aé🐻")

        XCTAssertEqual(runtimeStringValue(kk_string_substring(textRaw, 1, 3, 1, nil)), "é🐻")
        XCTAssertEqual(kk_string_indexOf(textRaw, rawFromRuntimeString("é🐻")), 1)
        XCTAssertEqual(kk_string_lastIndexOf(textRaw, rawFromRuntimeString("é")), 1)
    }

    func testStringCodePointCountUsesUTF16Ranges() {
        let textRaw = rawFromRuntimeString("a😀b")

        XCTAssertEqual(kk_string_codePointCount(textRaw), 3)

        var thrown = 0
        XCTAssertEqual(kk_string_codePointCount_from(textRaw, 1, &thrown), 2)
        XCTAssertEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_string_codePointCount_range(textRaw, 1, 3, &thrown), 1)
        XCTAssertEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_string_codePointCount_range(textRaw, 0, 2, &thrown), 2)
        XCTAssertEqual(thrown, 0)
    }

    func testStringCodePointCountReportsRangeErrors() {
        let textRaw = rawFromRuntimeString("abc")

        var thrown = 0
        XCTAssertEqual(kk_string_codePointCount_range(textRaw, -1, 1, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_string_codePointCount_range(textRaw, 0, 4, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)

        thrown = 0
        XCTAssertEqual(kk_string_codePointCount_range(textRaw, 2, 1, &thrown), 0)
        XCTAssertNotEqual(thrown, 0)
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

    // MARK: - STDLIB-TEXT-FN-055: replace overloads

    // STDLIB-TEXT-FN-012: kk_string_contains_ignoreCase
    //
    // Asserts the raw Boolean scalar returned by `kk_string_contains_ignoreCase`
    // matches Kotlin's `CharSequence.contains(other, ignoreCase)` semantics:
    // - empty needle always matches (mirroring `String.contains("")`)
    // - case-sensitive mode (`ignoreCase = false`) behaves like `kk_string_contains_str`
    // - case-insensitive mode matches across mixed-case ASCII without copying
    //   into a normalized scratch buffer.

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
            let raw = kk_string_toDouble(rawFromRuntimeString(source), &thrown)
            XCTAssertEqual(thrown, 0, "Expected \(source) to parse")
            XCTAssertEqual(doubleFromRuntimeBits(raw), expected, accuracy: 1e-12)
        }
    }

    func testStringToDoubleRejectsSwiftOnlySpellings() {
        var thrown = 0

        _ = kk_string_toDouble(rawFromRuntimeString("nan"), &thrown)
        XCTAssertNotEqual(thrown, 0)
        let thrownOutput = capturePrintln { kk_println_any(UnsafeMutableRawPointer(bitPattern: thrown)) }
        XCTAssertTrue(thrownOutput.contains("NumberFormatException"))

        XCTAssertEqual(kk_string_toDoubleOrNull(rawFromRuntimeString("inf")), runtimeNullSentinelInt)

        let parsed = kk_string_toDoubleOrNull(rawFromRuntimeString("0x1p2D"))
        XCTAssertNotEqual(parsed, runtimeNullSentinelInt)
        XCTAssertEqual(doubleFromRuntimeBits(parsed), 4.0, accuracy: 1e-12)
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

    private func makeRuntimeValueList(_ values: [RuntimeValue]) -> Int {
        registerRuntimeObject(RuntimeListBox(values: values))
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

}
