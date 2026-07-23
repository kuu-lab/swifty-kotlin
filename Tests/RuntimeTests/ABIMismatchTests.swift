import RuntimeABI
import XCTest

final class ABIMismatchTests: XCTestCase {
    // MARK: - Helpers

    private func requireSpec(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> RuntimeABIFunctionSpec {
        let spec = RuntimeABISpec.allFunctions.first(where: { $0.name == name })
        return try XCTUnwrap(spec, "'\(name)' not found in RuntimeABISpec.allFunctions", file: file, line: line)
    }

    // MARK: - Spec Integrity

    func testAllParameterNamesAreNonEmpty() {
        for spec in RuntimeABISpec.allFunctions {
            for param in spec.parameters {
                XCTAssertFalse(
                    param.name.isEmpty,
                    "Parameter in '\(spec.name)' has an empty name"
                )
            }
        }
    }

    func testParameterNamesUniquePerFunction() {
        for spec in RuntimeABISpec.allFunctions {
            let names = spec.parameters.map { $0.name }
            let uniqueNames = Set(names)
            XCTAssertEqual(
                names.count,
                uniqueNames.count,
                "Duplicate parameter names in '\(spec.name)'"
            )
        }
    }

    func testFloorDivABISignatures() throws {
        for name in ["kk_op_floor_div", "kk_op_lfloor_div"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .intptr)
            XCTAssertEqual(spec.parameters.map(\.type), [.intptr, .intptr])
            XCTAssertEqual(spec.parameters.map { $0.name }, ["lhs", "rhs"])
        }
    }

    // MARK: - J16.1 Signature Verification (spec-fixed)

    func testKKAllocSignature() throws {
        let spec = try requireSpec("kk_alloc")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "size")
        XCTAssertEqual(spec.parameters[0].type, .uint32)
        XCTAssertEqual(spec.parameters[1].name, "typeInfo")
        XCTAssertEqual(spec.parameters[1].type, .constTypeInfoPointer,
                       "kk_alloc typeInfo must be const KTypeInfo * per J16.1")
    }

    func testKKGcCollectSignature() throws {
        let spec = try requireSpec("kk_gc_collect")
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKThreadLocalNewSignature() throws {
        let spec = try requireSpec("kk_thread_local_new")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKThreadLocalGetOrSetSignature() throws {
        let spec = try requireSpec("kk_thread_local_getOrSet")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "receiver")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKThreadCreateSignature() throws {
        let spec = try requireSpec("kk_thread_create")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 7)
        XCTAssertEqual(spec.parameters[0].name, "start")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "isDaemon")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "contextClassLoaderRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "nameRaw")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
        XCTAssertEqual(spec.parameters[4].name, "priority")
        XCTAssertEqual(spec.parameters[4].type, .intptr)
        XCTAssertEqual(spec.parameters[5].name, "fnPtr")
        XCTAssertEqual(spec.parameters[5].type, .intptr)
        XCTAssertEqual(spec.parameters[6].name, "closureRaw")
        XCTAssertEqual(spec.parameters[6].type, .intptr)
    }

    func testKKThrowableNewSignature() throws {
        let spec = try requireSpec("kk_throwable_new")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
    }

    func testKKFloorModSignatures() throws {
        for name in ["kk_op_floor_mod", "kk_op_lfloor_mod"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .intptr)
            XCTAssertEqual(spec.parameters.map(\.type), [.intptr, .intptr])
        }
    }

    func testKKThrowablePrintStackTraceSignature() throws {
        let spec = try requireSpec("kk_throwable_printStackTrace")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKNoWhenBranchMatchedExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("kk_no_when_branch_matched_exception_new")
        XCTAssertEqual(noArg.returnType, .intptr)
        XCTAssertEqual(noArg.parameters.count, 0)

        let message = try requireSpec("kk_no_when_branch_matched_exception_new_message")
        XCTAssertEqual(message.returnType, .intptr)
        XCTAssertEqual(message.parameters.map(\.type), [.intptr])

        let messageCause = try requireSpec("kk_no_when_branch_matched_exception_new_message_cause")
        XCTAssertEqual(messageCause.returnType, .intptr)
        XCTAssertEqual(messageCause.parameters.map(\.type), [.intptr, .intptr])

        let cause = try requireSpec("kk_no_when_branch_matched_exception_new_cause")
        XCTAssertEqual(cause.returnType, .intptr)
        XCTAssertEqual(cause.parameters.map(\.type), [.intptr])
    }

    func testKKConcurrentModificationExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("kk_concurrent_modification_exception_new")
        XCTAssertEqual(noArg.returnType, .intptr)
        XCTAssertEqual(noArg.parameters.count, 0)

        let message = try requireSpec("kk_concurrent_modification_exception_new_message")
        XCTAssertEqual(message.returnType, .intptr)
        XCTAssertEqual(message.parameters.map(\.type), [.intptr])

        let messageCause = try requireSpec("kk_concurrent_modification_exception_new_message_cause")
        XCTAssertEqual(messageCause.returnType, .intptr)
        XCTAssertEqual(messageCause.parameters.map(\.type), [.intptr, .intptr])

        let cause = try requireSpec("kk_concurrent_modification_exception_new_cause")
        XCTAssertEqual(cause.returnType, .intptr)
        XCTAssertEqual(cause.parameters.map(\.type), [.intptr])
    }

    func testKKArrayIndexOutOfBoundsExceptionConstructorsSignature() throws {
        let noArg = try requireSpec("kk_array_index_out_of_bounds_exception_new")
        XCTAssertEqual(noArg.returnType, .intptr)
        XCTAssertEqual(noArg.parameters.count, 0)

        let message = try requireSpec("kk_array_index_out_of_bounds_exception_new_message")
        XCTAssertEqual(message.returnType, .intptr)
        XCTAssertEqual(message.parameters.map(\.type), [.intptr])
    }

    func testKKThrowableIsCancellationSignature() throws {
        let spec = try requireSpec("kk_throwable_is_cancellation")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKThrowableSuppressedExceptionsSignature() throws {
        let spec = try requireSpec("kk_throwable_suppressedExceptions")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKStringFromUTF8Signature() throws {
        let spec = try requireSpec("kk_string_from_utf8")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .constUInt8Pointer)
        XCTAssertEqual(spec.parameters[1].type, .int32)
    }

    func testKKStringConcatPointerABIRemoved() {
        XCTAssertFalse(
            RuntimeABISpec.allFunctions.contains { $0.name == "kk_string_concat" },
            "String concat should use kk_string_concat_flat instead of the legacy pointer ABI"
        )
    }

    func testKKStringRepeatPointerABIRemoved() {
        XCTAssertFalse(
            RuntimeABISpec.allFunctions.contains { $0.name == "kk_string_repeat" },
            "String repeat should use kk_string_repeat_flat instead of the legacy pointer ABI"
        )
    }

    func testKKStringSubstringAndReplaceSegmentPointerABIRemoved() {
        let legacyNames = [
            "kk_string_substringBefore",
            "kk_string_substringBefore_char",
            "kk_string_substringBeforeLast",
            "kk_string_substringBeforeLast_char",
            "kk_string_substringAfter",
            "kk_string_substringAfter_char",
            "kk_string_substringAfterLast",
            "kk_string_substringAfterLast_char",
            "kk_string_replaceAfter",
            "kk_string_replaceAfter_char",
            "kk_string_replaceAfterLast",
            "kk_string_replaceAfterLast_char",
            "kk_string_replaceBefore",
            "kk_string_replaceBefore_char",
            "kk_string_replaceBeforeLast",
            "kk_string_replaceBeforeLast_char",
        ]
        for legacyName in legacyNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringConcatFlatSignature() throws {
        let spec = try requireSpec("kk_string_concat_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.count, 11)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringReplacePointerABIRemoved() {
        let legacyNames = [
            "kk_string_replace",
            "kk_string_replace_char",
            "kk_string_replace_ignoreCase",
            "kk_string_replace_char_ignoreCase",
        ]
        for legacyName in legacyNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringRemovePrefixSuffixSurroundingPointerABIRemoved() {
        let legacyNames = [
            "kk_string_removePrefix",
            "kk_string_removeSuffix",
            "kk_string_removeSurrounding",
            "kk_string_removeSurrounding_pair",
        ]
        for legacyName in legacyNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringReplaceFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.count, 15)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringReplaceCharFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_char_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.count, 9)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringReplaceIgnoreCaseFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_ignoreCase_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.count, 16)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringReplaceCharIgnoreCaseFlatSignature() throws {
        let spec = try requireSpec("kk_string_replace_char_ignoreCase_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.count, 10)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringReplaceFirstRangePointerABIRemoved() {
        let legacyNames = [
            "kk_string_replaceFirst",
            "kk_string_replaceFirst_ignoreCase",
            "kk_string_replaceRange",
            "kk_string_removeRange",
            "kk_string_removeRange_range",
        ]
        for legacyName in legacyNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringReplaceFirstFlatSignature() throws {
        let spec = try requireSpec("kk_string_replaceFirst_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.count, 15)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringReplaceRangeFlatSignature() throws {
        let spec = try requireSpec("kk_string_replaceRange_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.count, 13)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringRemoveRangeFlatSignatures() throws {
        let indexed = try requireSpec("kk_string_removeRange_flat")
        XCTAssertEqual(indexed.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(indexed.parameters.count, 10)
        XCTAssertEqual(indexed.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])

        let ranged = try requireSpec("kk_string_removeRange_range_flat")
        XCTAssertEqual(ranged.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(ranged.parameters.count, 9)
        XCTAssertEqual(ranged.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringPadPointerABIRemoved() {
        let legacyNames = [
            "kk_string_padStart_default",
            "kk_string_padEnd_default",
            "kk_string_padStart",
            "kk_string_padEnd",
        ]
        for legacyName in legacyNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringPadDefaultFlatSignatures() throws {
        for name in ["kk_string_padStart_default_flat", "kk_string_padEnd_default_flat"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
            XCTAssertEqual(spec.parameters.count, 8)
            XCTAssertEqual(spec.parameters.map(\.type), [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    func testKKStringPadExplicitFlatSignatures() throws {
        for name in ["kk_string_padStart_flat", "kk_string_padEnd_flat"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
            XCTAssertEqual(spec.parameters.count, 9)
            XCTAssertEqual(spec.parameters.map(\.type), [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    func testKKStringTrimPointerABIRemoved() {
        let legacyNames = [
            "kk_string_trim",
            "kk_string_trim_predicate",
            "kk_string_trimStart",
            "kk_string_trimStart_predicate",
            "kk_string_trimEnd",
            "kk_string_trimEnd_predicate",
        ]
        for legacyName in legacyNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringTrimPredicateFlatSignatures() throws {
        let names = [
            "kk_string_trim_predicate_flat",
            "kk_string_trimStart_predicate_flat",
            "kk_string_trimEnd_predicate_flat",
        ]
        for name in names {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
            XCTAssertEqual(spec.parameters.count, 10)
            XCTAssertEqual(spec.parameters.map(\.type), [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    func testKKStringIfBlankEmptyFlatSignatures() throws {
        for name in ["kk_string_ifBlank_flat", "kk_string_ifEmpty_flat"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
            XCTAssertEqual(spec.parameters.count, 10)
            XCTAssertEqual(spec.parameters.map(\.type), [
                .nullableConstUInt8Pointer,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .intptr,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
                .nullableIntptrPointer,
            ])
        }
    }

    func testKKStringReplaceFirstCharPointerABIRemoved() {
        XCTAssertFalse(
            RuntimeABISpec.allFunctions.contains { $0.name == "kk_string_replaceFirstChar" },
            "kk_string_replaceFirstChar should use the flattened string ABI instead of the legacy pointer ABI"
        )
    }

    func testKKStringReplaceFirstCharFlatSignature() throws {
        let spec = try requireSpec("kk_string_replaceFirstChar_flat")
        XCTAssertEqual(spec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(spec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringCommonPrefixSuffixRuntimeABIRemoved() {
        let migratedNames = [
            "kk_string_commonPrefixWith",
            "kk_string_commonSuffixWith",
            "kk_string_commonPrefixWith_ignoreCase",
            "kk_string_commonSuffixWith_ignoreCase",
            "kk_string_commonPrefixWith_flat",
            "kk_string_commonSuffixWith_flat",
            "kk_string_commonPrefixWith_ignoreCase_flat",
            "kk_string_commonSuffixWith_ignoreCase_flat",
        ]
        for migratedName in migratedNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == migratedName },
                "\(migratedName) should be provided by bundled Kotlin source, not runtime ABI"
            )
        }
    }

    func testKKStringFormatPointerABIRemoved() {
        for legacyName in ["kk_string_format", "kk_string_format_locale"] {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringFormatFlatSignatures() throws {
        let formatSpec = try requireSpec("kk_string_format_flat")
        XCTAssertEqual(formatSpec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(formatSpec.parameters.map(\.type), [
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])

        let localeSpec = try requireSpec("kk_string_format_locale_flat")
        XCTAssertEqual(localeSpec.returnType, .nullableUInt8Pointer)
        XCTAssertEqual(localeSpec.parameters.map(\.type), [
            .intptr,
            .nullableConstUInt8Pointer,
            .intptr,
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringIndentPointerABIRemoved() {
        let legacyNames = [
            "kk_string_trimIndent",
            "kk_string_trimMargin_default",
            "kk_string_trimMargin",
            "kk_string_prependIndent_default",
            "kk_string_prependIndent",
            "kk_string_replaceIndent_default",
            "kk_string_replaceIndent",
            "kk_string_replaceIndentByMargin",
        ]
        for legacyName in legacyNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == legacyName },
                "\(legacyName) should use the flattened string ABI instead of the legacy pointer ABI"
            )
        }
    }

    func testKKStringIndentSourceBridgeSignatures() throws {
        let trimIndent = try requireSpec("__kk_string_trimIndent")
        XCTAssertEqual(trimIndent.returnType, .intptr)
        XCTAssertEqual(trimIndent.parameters.map(\.type), [.intptr])

        let trimMargin = try requireSpec("__kk_string_trimMargin")
        XCTAssertEqual(trimMargin.returnType, .intptr)
        XCTAssertEqual(trimMargin.parameters.map(\.type), [
            .intptr,
            .intptr,
            .nullableIntptrPointer,
        ])

        for name in ["__kk_string_prependIndent", "__kk_string_replaceIndent"] {
            let spec = try requireSpec(name)
            XCTAssertEqual(spec.returnType, .intptr)
            XCTAssertEqual(spec.parameters.map(\.type), [
                .intptr,
                .intptr,
            ])
        }

        let replaceByMargin = try requireSpec("__kk_string_replaceIndentByMargin")
        XCTAssertEqual(replaceByMargin.returnType, .intptr)
        XCTAssertEqual(replaceByMargin.parameters.map(\.type), [
            .intptr,
            .intptr,
            .intptr,
            .nullableIntptrPointer,
        ])
    }

    func testKKStringIndentFlatABIRemoved() {
        let flatNames = [
            "kk_string_trimIndent_flat",
            "kk_string_trimMargin_default_flat",
            "kk_string_trimMargin_flat",
            "kk_string_prependIndent_default_flat",
            "kk_string_prependIndent_flat",
            "kk_string_replaceIndent_default_flat",
            "kk_string_replaceIndent_flat",
            "kk_string_replaceIndentByMargin_flat",
        ]
        for name in flatNames {
            XCTAssertFalse(
                RuntimeABISpec.allFunctions.contains { $0.name == name },
                "\(name) should be provided by bundled Kotlin source, not the flattened runtime ABI"
            )
        }
    }

    func testKKPrintlnAnySignature() throws {
        let spec = try requireSpec("kk_println_any")
        XCTAssertEqual(spec.returnType, .void)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .nullableOpaquePointer)
    }

    func testStringLengthHasNoRuntimeABISignature() {
        XCTAssertNil(
            RuntimeABISpec.allFunctions.first(where: { $0.name == "kk_string_struct_get_length" }),
            "String.length is lowered as an aggregate field extract and must not have a runtime ABI entry"
        )
    }

    func testKKOpIsSignature() throws {
        let spec = try requireSpec("kk_op_is")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
    }

    func testKKCoroutineSuspendedSignature() throws {
        let spec = try requireSpec("kk_coroutine_suspended")
        XCTAssertEqual(spec.returnType, .opaquePointer)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKCreateCoroutineUninterceptedSignature() throws {
        let spec = try requireSpec("kk_create_coroutine_unintercepted")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "entryPointRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "completionContinuation")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
    }

    func testKKStartCoroutineUninterceptedOrReturnSignature() throws {
        let spec = try requireSpec("kk_start_coroutine_unintercepted_or_return")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "entryPointRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "continuation")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "outThrown")
        XCTAssertEqual(spec.parameters[2].type, .nullableIntptrPointer)
    }

    func testKKSuspendFunctionInvokeSignature() throws {
        let spec = try requireSpec("kk_suspend_function_invoke")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "functionRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "arg")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "outThrown")
        XCTAssertEqual(spec.parameters[2].type, .nullableIntptrPointer)
    }

    func testKKSuspendFunctionInvokeZeroAritySignature() throws {
        let spec = try requireSpec("kk_suspend_function_invoke_0")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "functionRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "outThrown")
        XCTAssertEqual(spec.parameters[1].type, .nullableIntptrPointer)
    }

    func testKKMutableListAddAtSignature() throws {
        let spec = try requireSpec("kk_mutable_list_add_at")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "index")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "element")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKMutableListSetSignature() throws {
        let spec = try requireSpec("kk_mutable_list_set")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "index")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "element")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKListSubtractSignature() throws {
        let spec = try requireSpec("kk_list_subtract")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
    }

    func testKKListSortedSignature() throws {
        let spec = try requireSpec("kk_list_sorted")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKListSortedPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sorted_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .int32)
    }

    func testKKListSortedDescendingSignature() throws {
        let spec = try requireSpec("kk_list_sortedDescending")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKListSortedBySignature() throws {
        let spec = try requireSpec("kk_list_sortedBy")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKListSortedByPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sortedBy_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKListSortedByDescendingSignature() throws {
        let spec = try requireSpec("kk_list_sortedByDescending")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKListSortedByDescendingPrimitiveSignature() throws {
        let spec = try requireSpec("kk_list_sortedByDescending_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKListSortedWithSignature() throws {
        let spec = try requireSpec("kk_list_sortedWith")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKListSumOfSignature() throws {
        let spec = try requireSpec("kk_list_sumOf")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKListSumSignature() throws {
        let spec = try requireSpec("kk_list_sum")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKListSumByDoubleSignature() throws {
        let spec = try requireSpec("kk_list_sumByDouble")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKListSumBySignature() throws {
        let spec = try requireSpec("kk_list_sumBy")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKMutableListSortSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sort")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKMutableListSortPrimitiveSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sort_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .int32)
    }

    func testKKMutableListSortBySignature() throws {
        let spec = try requireSpec("kk_mutable_list_sortBy")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKMutableListSortWithSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sortWith")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKMutableListSortByPrimitiveSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sortBy_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKMutableListSortByDescendingSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sortByDescending")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
    }

    func testKKMutableListSortByDescendingPrimitiveSignature() throws {
        let spec = try requireSpec("kk_mutable_list_sortByDescending_primitive")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].type, .int32)
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
    }

    func testKKLockWithLockSignature() throws {
        let spec = try requireSpec("kk_lock_withLock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
    }

    func testKKMutexCreateSignature() throws {
        let spec = try requireSpec("kk_mutex_create")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKReadWriteLockCreateSignature() throws {
        let spec = try requireSpec("kk_read_write_lock_create")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 0)
    }

    func testKKMutexLockSignature() throws {
        let spec = try requireSpec("kk_mutex_lock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 2)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "continuation")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
    }

    func testKKMutexUnlockSignature() throws {
        let spec = try requireSpec("kk_mutex_unlock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKMutexTryLockSignature() throws {
        let spec = try requireSpec("kk_mutex_tryLock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKMutexIsLockedSignature() throws {
        let spec = try requireSpec("kk_mutex_isLocked")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 1)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
    }

    func testKKMutexWithLockSignature() throws {
        let spec = try requireSpec("kk_mutex_withLock")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "continuation")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
    }

    func testKKReadWriteLockReadSignature() throws {
        let spec = try requireSpec("kk_read_write_lock_read")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
    }

    func testKKReadWriteLockWriteSignature() throws {
        let spec = try requireSpec("kk_read_write_lock_write")
        XCTAssertEqual(spec.returnType, .intptr)
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "handle")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "actionFnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "actionEnvPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
    }

    // MARK: - Collection HOF Scan/Reduce (STDLIB-526..530)

    func testKKListReduceOrNullSignature() throws {
        let spec = try requireSpec("kk_list_reduceOrNull")
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListScanReduceSignature() throws {
        let spec = try requireSpec("kk_list_scanReduce")
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListScanSignature() throws {
        let spec = try requireSpec("kk_list_scan")
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "initial")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "fnPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "closureRaw")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
        XCTAssertEqual(spec.parameters[4].name, "outThrown")
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListRunningFoldSignature() throws {
        let spec = try requireSpec("kk_list_runningFold")
        XCTAssertEqual(spec.parameters.count, 5)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "initial")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "fnPtr")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "closureRaw")
        XCTAssertEqual(spec.parameters[3].type, .intptr)
        XCTAssertEqual(spec.parameters[4].name, "outThrown")
        XCTAssertEqual(spec.parameters[4].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListRunningReduceSignature() throws {
        let spec = try requireSpec("kk_list_runningReduce")
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListTakeSignature() throws {
        let spec = try requireSpec("kk_list_take")
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "count")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "outThrown")
        XCTAssertEqual(spec.parameters[2].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    func testKKListTakeLastSignature() throws {
        let spec = try requireSpec("kk_list_takeLast")
        XCTAssertEqual(spec.parameters.count, 3)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "count")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "outThrown")
        XCTAssertEqual(spec.parameters[2].type, .nullableIntptrPointer)
    }

    func testKKListTakeWhileSignature() throws {
        let spec = try requireSpec("kk_list_takeWhile")
        XCTAssertEqual(spec.parameters.count, 4)
        XCTAssertEqual(spec.parameters[0].name, "listRaw")
        XCTAssertEqual(spec.parameters[0].type, .intptr)
        XCTAssertEqual(spec.parameters[1].name, "fnPtr")
        XCTAssertEqual(spec.parameters[1].type, .intptr)
        XCTAssertEqual(spec.parameters[2].name, "closureRaw")
        XCTAssertEqual(spec.parameters[2].type, .intptr)
        XCTAssertEqual(spec.parameters[3].name, "outThrown")
        XCTAssertEqual(spec.parameters[3].type, .nullableIntptrPointer)
        XCTAssertEqual(spec.returnType, .intptr)
    }

    // MARK: - Header Generation

    func testGeneratedHeaderContainsGuard() {
        let header = RuntimeABISpec.generateCHeader()
        XCTAssertTrue(header.contains("#ifndef KK_RUNTIME_ABI_H"))
        XCTAssertTrue(header.contains("#define KK_RUNTIME_ABI_H"))
        XCTAssertTrue(header.contains("#endif"))
    }

    func testGeneratedHeaderContainsAllFunctions() {
        let header = RuntimeABISpec.generateCHeader()
        let headerLines = Set(
            header
                .split(separator: "\n")
                .map { String($0).trimmingCharacters(in: .whitespaces) }
        )
        for spec in RuntimeABISpec.allFunctions {
            XCTAssertTrue(
                headerLines.contains(spec.cDeclaration),
                "Generated header missing declaration for '\(spec.name)': expected line '\(spec.cDeclaration)'"
            )
        }
    }

    func testGeneratedHeaderContainsSpecVersion() {
        let header = RuntimeABISpec.generateCHeader()
        XCTAssertTrue(header.contains(RuntimeABISpec.specVersion))
    }

}
