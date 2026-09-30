Warning: truncated output (original token count: 42293)
Total output lines: 3568

// swiftlint:disable file_length
import RuntimeABI
import CompilerCore

extension NativeEmitter {
    private struct FlatStringReturnCallSpec {
        let flatName: String
        let stringArgumentCount: Int
        let extraArgumentCount: Int
        let stringArgumentPositions: [Int]
        let canThrow: Bool

        init(
            flatName: String,
            stringArgumentCount: Int,
            extraArgumentCount: Int,
            stringArgumentPositions: [Int]? = nil,
            canThrow: Bool
        ) {
            self.flatName = flatName
            self.stringArgumentCount = stringArgumentCount
            self.extraArgumentCount = extraArgumentCount
            self.stringArgumentPositions = stringArgumentPositions ?? Array(0..<stringArgumentCount)
            self.canThrow = canThrow
        }
    }

    private struct FlatScalarReturnCallSpec {
        let flatName: String
        let stringArgumentCount: Int
        let extraArgumentCount: Int
        let stringArgumentPositions: [Int]
        let canThrow: Bool
        let defaultMissingClosureRaw: Bool

        init(
            flatName: String,
            stringArgumentCount: Int,
            extraArgumentCount: Int,
            stringArgumentPositions: [Int]? = nil,
            canThrow: Bool = false,
            defaultMissingClosureRaw: Bool = false
        ) {
            self.flatName = flatName
            self.stringArgumentCount = stringArgumentCount
            self.extraArgumentCount = extraArgumentCount
            self.stringArgumentPositions = stringArgumentPositions ?? Array(0..<stringArgumentCount)
            self.canThrow = canThrow
            self.defaultMissingClosureRaw = defaultMissingClosureRaw
        }
    }

    private static let flatStringReturnCallSpecs: [String: FlatStringReturnCallSpec] = {
        var specs: [String: FlatStringReturnCallSpec] = [
            "kk_string_to_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_to_flat",
                stringArgumentCount: 0,
                extraArgumentCount: 1,
                canThrow: false
            ),
            "__kk_string_concat_flat": FlatStringReturnCallSpec(
                flatName: "__kk_string_concat_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 0,
                canThrow: false
            ),
            "kk_string_trim_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_trim_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: false
            ),
            "kk_string_trim_predicate_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_trim_predicate_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                canThrow: true
            ),
            "kk_string_trimStart_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_trimStart_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: false
            ),
            "kk_string_trimStart_predicate_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_trimStart_predicate_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                canThrow: true
            ),
            "kk_string_trimEnd_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_trimEnd_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: false
            ),
            "kk_string_trimEnd_predicate_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_trimEnd_predicate_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                canThrow: true
            ),
            "kk_string_lowercase_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_lowercase_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: false
            ),
            "kk_string_uppercase_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_uppercase_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: false
            ),
            "__kk_lowercase_locale_flat": FlatStringReturnCallSpec(
                flatName: "__kk_lowercase_locale_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: false
            ),
            "__kk_uppercase_locale_flat": FlatStringReturnCallSpec(
                flatName: "__kk_uppercase_locale_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: false
            ),
            "__kk_string_normalize_flat": FlatStringReturnCallSpec(
                flatName: "__kk_string_normalize_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: false
            ),
            "kk_string_orEmpty_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_orEmpty_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: false
            ),
            // KSP-1396: reversed is bundled Kotlin source (StringBasics.kt);
            // no flat emission spec.
            // KSP-410: filter/filterNot/filterIndexed are bundled Kotlin
            // source (StringHOF.kt); no flat emission spec.
            // Source-backed declarations retain flat compatibility lowering
            // for aggregate String receivers.
            "kk_string_ifBlank_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_ifBlank_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                canThrow: true
            ),
            "kk_string_ifEmpty_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_ifEmpty_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                canThrow: true
            ),
            // KSP-405: takeWhile/takeLastWhile/dropWhile are bundled Kotlin
            // source (StringTakeDrop.kt); no flat emission spec.
            "kk_string_replace_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_replace_flat",
                stringArgumentCount: 3,
                extraArgumentCount: 0,
                canThrow: false
            ),
            "kk_string_replace_char_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_replace_char_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                canThrow: false
            ),
            "kk_string_replace_ignoreCase_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_replace_ignoreCase_flat",
                stringArgumentCount: 3,
                extraArgumentCount: 1,
                canThrow: false
            ),
            "kk_string_replace_char_ignoreCase_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_replace_char_ignoreCase_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 3,
                canThrow: false
            ),
            "kk_string_replaceFirst_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_replaceFirst_flat",
                stringArgumentCount: 3,
                extraArgumentCount: 0,
                canThrow: false
            ),
            // KSP-406: substring/subSequence/slice/removeRange/replaceRange are
            // bundled Kotlin source (StringSubstringSlice.kt); no flat emission spec.
            // KSP-1390: padStart/padEnd are bundled Kotlin source
            // (StringHOF.kt); no flat emission spec.
            // KSP-1394: repeat is bundled Kotlin source (StringBasics.kt);
            // no flat emission spec.
            // KSP-405: take/takeLast/drop/dropLast are bundled Kotlin source
            // (StringTakeDrop.kt); no flat emission spec.
            // KSP-404: removePrefix/removeSuffix/removeSurrounding are bundled
            // Kotlin source (StringPrefixSuffix.kt); no flat emission spec.
            // KSP-407: substringBefore/After/BeforeLast/AfterLast and
            // replaceBefore/After/BeforeLast/AfterLast are bundled Kotlin
            // source (StringSearchReplace.kt); no flat emission spec.
            "__kk_string_format_flat": FlatStringReturnCallSpec(
                flatName: "__kk_string_format_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [0],
                canThrow: false
            ),
            "__kk_string_format_locale_flat": FlatStringReturnCallSpec(
                flatName: "__kk_string_format_locale_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                stringArgumentPositions: [1],
                canThrow: false
            ),
        ]
        for spec in Array(specs.values)
        where specs[spec.flatName] == nil {
            specs[spec.flatName] = spec
        }
        return specs
    }()

    private static let flatScalarReturnCallSpecs: [String: FlatScalarReturnCallSpec] = {
        var specs: [String: FlatScalarReturnCallSpec] = [
            "kk_string_from_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_from_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_locale_new_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_locale_new_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_locale_new_language_country_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_locale_new_language_country_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 0
            ),
            "kk_string_split_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_split_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 0
            ),
            "kk_string_split_limit_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_split_limit_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 2
            ),
            "kk_string_splitToSequence_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_splitToSequence_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 0
            ),
            "__kk_regex_create_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_create_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_regex_create_with_option_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_create_with_option_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_regex_create_with_options_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_create_with_options_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_matches_regex_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_matches_regex_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
            "__kk_string_contains_regex_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_contains_regex_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
            "__kk_string_split_regex_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_split_regex_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
            "__kk_string_toRegex_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toRegex_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toRegex_with_option_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toRegex_with_option_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toRegex_with_options_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toRegex_with_options_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_regex_find_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_find_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_regex_findAll_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_findAll_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_regex_matchEntire_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_matchEntire_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_regex_containsMatchIn_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_containsMatchIn_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_regex_from_literal_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_from_literal_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_match_result_group_index_of_name": FlatScalarReturnCallSpec(
                flatName: "__kk_match_result_group_index_of_name_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_regex_matches_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_regex_matches_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_string_builder_new_from_string_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_builder_new_from_string_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_builder_append_obj": FlatScalarReturnCallSpec(
                flatName: "__kk_string_builder_append_obj_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                stringArgumentPositions: [1]
            ),
            "__kk_string_builder_toString": FlatScalarReturnCallSpec(
                flatName: "__kk_string_builder_toString",
                stringArgumentCount: 0,
                extraArgumentCount: 1
            ),
            "__kk_bignum_toString": FlatScalarReturnCallSpec(
                flatName: "__kk_bignum_toString",
                stringArgumentCount: 0,
                extraArgumentCount: 1
            ),
            // KSP-404: startsWith/endsWith are bundled Kotlin source
            // (StringPrefixSuffix.kt); no flat emission spec.
            // KSP-408: contains/indexOf/lastIndexOf/indexOfAny/lastIndexOfAny/
            // findAnyOf/findLastAnyOf are bundled Kotlin source (StringIndexOf.kt);
            // no flat emission spec.
            // KSP-413: compareTo(ignoreCase) / contentEquals / equals(ignoreCase)
            // are bundled Kotlin source (StringComparison.kt); no flat emission spec.
            "kk_string_compareTo_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_compareTo_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 0
            ),
            "__kk_string_compareTo_locale_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_compareTo_locale_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 1
            ),
            "__kk_string_isNormalized_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_isNormalized_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
            "__kk_string_equals_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_equals_flat",
                stringArgumentCount: 2,
                extraArgumentCount: 0
            ),
            "kk_string_isEmpty_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_isEmpty_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "kk_string_isNotEmpty_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_isNotEmpty_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "kk_string_isBlank_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_isBlank_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "kk_string_isNotBlank_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_isNotBlank_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "kk_string_isNullOrEmpty_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_isNullOrEmpty_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "kk_string_isNullOrBlank_flat": FlatScalarReturnCallSpec(
                flatName: "kk_string_isNullOrBlank_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_first_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_first_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_last_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_last_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_single_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_single_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_firstOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_firstOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_lastOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_lastOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_singleOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_singleOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_getOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_getOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
            "__kk_string_get_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_get_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            // KSP-408: indexOfFirst/indexOfLast are bundled Kotlin source
            // (StringIndexOf.kt); no flat emission spec.
            // KSP-410: count/any/all/none/find/findLast/partition and
            // map/mapIndexed/mapNotNull/firstNotNullOf(OrNull) are bundled
            // Kotlin source (StringHOF.kt); no flat emission spec.
            // KSP-410: sumBy/sumByDouble/reduceOrNull/reduceRightIndexed/
            // reduceRightIndexedOrNull/reduceRightOrNull are bundled
            // Kotlin source (StringHOF.kt); no flat emission spec.
            "__kk_string_toBoolean_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toBoolean_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toBooleanStrict_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toBooleanStrict_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toBooleanStrictOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toBooleanStrictOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toInt_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toInt_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toInt_radix_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toInt_radix_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toIntOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toIntOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toIntOrNull_radix_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toIntOrNull_radix_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toUByteOrNull_radix_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toUByteOrNull_radix_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toUShortOrNull_radix_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toUShortOrNull_radix_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toUIntOrNull_radix_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toUIntOrNull_radix_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toULongOrNull_radix_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toULongOrNull_radix_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toDouble_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toDouble_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toDoubleOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toDoubleOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toLong_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toLong_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toLongOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toLongOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toFloat_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toFloat_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toFloatOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toFloatOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toShort_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toShort_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toShortOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toShortOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toByte_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toByte_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toByte_radix_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toByte_radix_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1,
                canThrow: true
            ),
            "__kk_string_toByteOrNull_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toByteOrNull_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toBigDecimal_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toBigDecimal_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0,
                canThrow: true
            ),
            "__kk_string_toByteArray_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toByteArray_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_toByteArray_charset_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_toByteArray_charset_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
            "__kk_string_encodeToByteArray_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_encodeToByteArray_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_encodeToByteArray_range_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_encodeToByteArray_range_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2
            ),
            "__kk_string_encodeToByteArray_charset_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_encodeToByteArray_charset_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
            "__kk_string_byteInputStream_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_byteInputStream_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 0
            ),
            "__kk_string_byteInputStream_charset_flat": FlatScalarReturnCallSpec(
                flatName: "__kk_string_byteInputStream_charset_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 1
            ),
        ]
        for spec in Array(specs.values)
        where specs[spec.flatName] == nil {
            specs[spec.flatName] = spec
        }
        return specs
    }()

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func emitFunctionBody(
        function: KIRFunction,
        llvmFunction: LLVMFunction,
        llvmModule: LLVMCAPIBindings.LLVMModuleRef,
        context: LLVMCAPIBindings.LLVMContextRef,
        int64Type: LLVMCAPIBindings.LLVMTypeRef,
        typeLowering: LLVMTypeLowering?,
        outThrownPointerType: LLVMCAPIBindings.LLVMTypeRef,
        internalFunctions: [SymbolID: LLVMFunction],
        internalSignatures: [SymbolID: (parameters: [TypeID], returnType: TypeID)],
        internalFunctionsByLookupKey: [FunctionLookupKey: [KIRFunction]],
        globalVariables: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:],
        runtimeCallbackRawReturnSymbols: Set<SymbolID> = [],
        usesRuntimeCallbackRawABI: Bool = false,
        returnsRawStringRuntimeCallback: Bool = false,
        nameCounter: GeneratedNameCounter,
        diContext: DebugInfoContext? = nil
    ) throws {
        guard let builder = bindings.createBuilder(context: context) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMCreateBuilderInContext returned null")
        }
        defer {
            // Clear debug location before disposing the builder.
            if diContext != nil {
                bindings.clearCurrentDebugLocation(builder)
            }
            bindings.disposeBuilder(builder)
        }

        // When debug info is active and the function has a subprogram,
        // set the function-level debug location so the LLVM verifier accepts
        // all instructions emitted under this builder.
        if let diContext,
           let subprogram = diContext.subprograms[function.symbol],
           bindings.debugLocationAvailable
        {
            var funcLine: UInt32 = 0
            var funcCol: UInt32 = 0
            if let sourceRange = function.sourceRange, let sm = sourceManager {
                let lc = sm.lineColumn(of: sourceRange.start)
                funcLine = UInt32(lc.line)
                funcCol = UInt32(lc.column)
            }
            if let loc = bindings.createDebugLocation(
                context: context,
                line: funcLine,
                column: funcCol,
                scope: subprogram
            ) {
                bindings.setCurrentDebugLocation(builder, location: loc)
            }
        }

        guard let entryBlock = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "entry") else {
            throw LLVMBackendError.nativeEmissionFailed("failed to create entry block")
        }

        // Dedicated builder for stack slots. Slots requested while a loop body is
        // being emitted must be allocated in the entry block, otherwise every
        // iteration allocates a fresh slot and long loops overflow the stack.
        let allocaBuilder = bindings.createBuilder(context: context)
        defer {
            if let allocaBuilder {
                bindings.disposeBuilder(allocaBuilder)
            }
        }

        func buildEntrySlot(name: String, type: LLVMCAPIBindings.LLVMTypeRef? = nil) -> LLVMCAPIBindings.LLVMValueRef? {
            bindings.buildEntryAlloca(
                type: type ?? int64Type,
                name: name,
                entryBlock: entryBlock,
                allocaBuilder: allocaBuilder,
                fallbackBuilder: builder
            )
        }

        var labelBlocks: [Int32: LLVMCAPIBindings.LLVMBasicBlockRef] = [:]
        for instruction in function.body {
            guard case let .label(id) = instruction else {
                continue
            }
            if labelBlocks[id] != nil {
                continue
            }
            if let block = bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: nameCounter.nextName("L")) {
                labelBlocks[id] = block
            }
        }

        var parameterValues: [SymbolID: LLVMCAPIBindings.LLVMValueRef] = [:]
        for (index, parameter) in function.params.enumerated() {
            guard let value = bindings.getParam(function: llvmFunction.value, index: UInt32(index)) else {
                continue
            }
            parameterValues[parameter.symbol] = value
        }

        // Position builder at the entry block before emitting parameter debug
        // info (alloca/store require a valid insert point).
        bindings.positionBuilder(builder, at: entryBlock)

        // Emit DILocalVariable + dbg.declare for each parameter when debug
        // info is active and the required bindings are available.
        if let diContext,
           let subprogram = diContext.subprograms[function.symbol],
           let int64DIType = diContext.int64DIType,
           bindings.localVariableAvailable,
           bindings.debugLocationAvailable
        {
            var funcLine: UInt32 = 0
            if let sourceRange = function.sourceRange, let sm = sourceManager {
                funcLine = UInt32(sm.lineColumn(of: sourceRange.start).line)
            }
            let funcDIFile: LLVMCAPIBindings.LLVMMetadataRef? = {
                if let sourceRange = function.sourceRange {
                    return diContext.diFiles[sourceRange.start.file] ?? diContext.file
                }
                return diContext.file
            }()
            let emptyExpr = bindings.diBuilderCreateExpression(diContext.diBuilder)
            for (index, parameter) in function.params.enumerated() {
                guard let paramValue = parameterValues[parameter.symbol] else {
                    continue
                }
                let paramName = "arg\(index)"
                guard let diVar = bindings.diBuilderCreateParameterVariable(
                    diContext.diBuilder,
                    scope: subprogram,
                    name: paramName,
                    argNo: UInt32(index + 1),
                    file: funcDIFile,
                    lineNo: funcLine,
                    type: int64DIType
                ) else {
                    continue
                }
                // Create an alloca for the parameter so dbg.declare can reference it.
                let parameterType = usesRuntimeCallbackRawABI
                    ? int64Type
                    : loweredLLVMType(
                        for: parameter.type,
                        lowering: typeLowering,
                        defaultType: int64Type
                    )
                let paramAlloca = bindings.buildAlloca(builder, type: parameterType, name: "dbg_\(paramName)")
                if let paramAlloca {
                    _ = bindings.buildStore(builder, value: paramValue, pointer: paramAlloca)
                    if let debugLoc = bindings.createDebugLocation(
                        context: context, line: funcLine, column: 0, scope: subprogram
                    ) {
                        _ = bindings.diBuilderInsertDeclareAtEnd(
                            diContext.diBuilder,
                            storage: paramAlloca,
                            varInfo: diVar,
                            expr: emptyExpr,
                            debugLoc: debugLoc,
                            block: entryBlock
                        )
                    }
                }
            }
        }
        let outThrownParameter = bindings.getParam(
            function: llvmFunction.value,
            index: UInt32(function.params.count)
        )

        guard let zeroValue = bindings.constInt(int64Type, value: 0) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMConstInt returned null")
        }
        let zeroReturnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
            zeroValue
        } else {
            zeroLLVMValue(
                for: function.returnType,
                lowering: typeLowering,
                int64Type: int64Type,
                context: context
            ) ?? zeroValue
        }
        guard let undefThrownPointer = bindings.getUndef(type: outThrownPointerType) else {
            throw LLVMBackendError.nativeEmissionFailed("LLVMGetUndef for outThrown pointer returned null")
        }
        let nullThrownPointer = bindings.constPointerNull(outThrownPointerType) ?? undefThrownPointer

        bindings.positionBuilder(builder, at: entryBlock)
        var currentBlock = entryBlock
        var values: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var rawResultValues: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        var externalFunctions: [String: LLVMFunction] = [:]
        let maxKIRArgumentCountByExternalCallee = Self.maxKIRArgumentCountByExternalCallee(
            body: function.body,
            interner: interner
        )
        let builderState = EmissionBuilderState(
            builder: builder,
            int64Type: int64Type,
            zeroValue: zeroValue,
            context: context,
            module: llvmModule,
            typeLowering: typeLowering,
            entryBlock: entryBlock,
            allocaBuilder: allocaBuilder
        )

        func assignmentTargets(for instruction: KIRInstruction) -> [KIRExprID] {
            switch instruction {
            case let .constValue(result, _):
                return [result]
            case let .binary(_, _, _, result):
                return [result]
            case let .unary(_, _, result):
                return [result]
            case let .nullAssert(_, result):
                return [result]
            case let .call(_, _, _, result, _, thrownResult, _, _):
                let directTargets = result.map { [$0] } ?? []
                let thrownTargets = thrownResult.map { [$0] } ?? []
                return directTargets + thrownTargets
            case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
                let directTargets = result.map { [$0] } ?? []
                let thrownTargets = thrownResult.map { [$0] } ?? []
                return directTargets + thrownTargets
            case let .copy(_, to):
                return [to]
            case let .loadGlobal(result, _):
                return [result]
            case .jump, .label, .jumpIfEqual, .jumpIfNotNull,
                 .storeGlobal, .rethrow, .returnIfEqual, .returnUnit, .returnValue,
                 .beginBlock, .endBlock, .nop, .nonLocalReturn,
                 .beginFinallyGuard, .endFinallyGuard:
                return []
            }
        }

        var assignmentTargetCounts: [Int32: Int] = [:]
        for instruction in function.body {
            for target in assignmentTargets(for: instruction) {
                assignmentTargetCounts[target.rawValue, default: 0] += 1
            }
        }

        // KIR temporaries are not strict SSA values: inline expansion and
        // throw-aware control flow can route multiple predecessor blocks to a
        // later use even when the temporary has only one syntactic assignment.
        // Keeping such a result as an LLVM SSA value produces invalid IR when
        // its defining block does not dominate the merge block. Materialize
        // assignment targets in entry-block slots; optimized pipelines promote
        // the safe cases back to SSA with mem2reg.
        let shouldSpillID = Set(assignmentTargetCounts.keys)

        var copyTargetAllocas: [Int32: LLVMCAPIBindings.LLVMValueRef] = [:]
        for instruction in function.body {
            for target in assignmentTargets(for: instruction) where shouldSpillID.contains(target.rawValue) {
                if copyTargetAllocas[target.rawValue] == nil,
                   let alloca = bindings.buildAlloca(
                       builder,
                       type: loweredLLVMType(
                           for: module.arena.exprType(target),
                           lowering: typeLowering,
                           defaultType: int64Type
                       ),
                       name: nameCounter.nextName("copy_slot_")
                   )
                {
                    let initialValue = zeroLLVMValue(
                        for: module.arena.exprType(target),
                        lowering: typeLowering,
                        int64Type: int64Type,
                        context: context
                    ) ?? zeroValue
                    _ = bindings.buildStore(builder, value: initialValue, pointer: alloca)
                    copyTargetAllocas[target.rawValue] = alloca
                }
            }
        }

        func declareExternalFunction(
            named calleeName: String,
            argumentCount: Int,
            appendThrownChannel: Bool
        ) -> LLVMFunction? {
            // String.length extension: redirect "length" (1 arg = receiver) to the
            // aggregate field accessor sentinel. Codegen lowers it to extractvalue.
            // Lambda bodies may reach codegen with callee "length" when receiver type is not
            // available during KIR lowering (e.g. mapIndexed { _, v -> v.length }).
            let effectiveName: String = if Self.isStringLengthAggregateAccessorName(calleeName),
                                           argumentCount == 1,
                                           !appendThrownChannel
            {
                "__kk_string_struct_get_length"
            } else {
                calleeName
            }
            if let existing = externalFunctions[effectiveName] {
                return existing
            }
            let maxArgsSeenInBody = maxKIRArgumentCountByExternalCallee[effectiveName] ?? 0
            let effectiveArgumentCount = max(argumentCount, maxArgsSeenInBody)
            var callParameterTypes = Array(repeating: int64Type, count: effectiveArgumentCount)
            if appendThrownChannel {
                callParameterTypes.append(outThrownPointerType)
            }
            guard let externalType = bindings.functionType(
                returnType: int64Type,
                parameters: callParameterTypes,
                isVarArg: false
            ) else {
                return nil
            }
            let externalValue = bindings.getNamedFunction(module: llvmModule, name: effectiveName)
                ?? bindings.addFunction(module: llvmModule, name: effectiveName, functionType: externalType)
            guard let externalValue else {
                return nil
            }
            let declared = LLVMFunction(value: externalValue, type: externalType)
            externalFunctions[effectiveName] = declared
            return declared
        }

        func declareExternalFunction(
            named calleeName: String,
            parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?],
            returnType: LLVMCAPIBindings.LLVMTypeRef?
        ) -> LLVMFunction? {
            let key = "\(calleeName)#typed#\(parameterTypes.count)"
            if let existing = externalFunctions[key] {
                return existing
            }
            guard let externalType = bindings.functionType(
                returnType: returnType,
                parameters: parameterTypes,
                isVarArg: false
            ) else {
                return nil
            }
            let externalValue = bindings.getNamedFunction(module: llvmModule, name: calleeName)
                ?? bindings.addFunction(module: llvmModule, name: calleeName, functionType: externalType)
            guard let externalValue else {
                return nil
            }
            let declared = LLVMFunction(value: externalValue, type: externalType)
            externalFunctions[key] = declared
            return declared
        }

        func stringAggregateFields(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> [LLVMCAPIBindings.LLVMValueRef]? {
            // `value`'s KIR-level semantic type may be String (i.e. isStringAggregateExpr
            // returned true) even when this particular expression was materialized as a
            // raw (boxed) Int64 handle rather than a flat struct — e.g. a HOF lambda
            // parameter sourced from a collection element. Extracting a struct field from
            // a non-aggregate LLVM value crashes LLVM, so confirm the actual LLVM value is
            // an aggregate first, bridging from the raw handle when it is not.
            let aggregate: LLVMCAPIBindings.LLVMValueRef
            if bindings.isAggregateStructValue(value) {
                aggregate = value
            } else if let bridged = bridgeRuntimeRawToStringAggregate(value, suffix: "\(suffix)_from_raw") {
                aggregate = bridged
            } else {
                return nil
            }
            guard let data = bindings.buildExtractValue(builder, aggregate: aggregate, index: 0, name: "str_data_\(suffix)"),
                  let length = bindings.buildExtractValue(builder, aggregate: aggregate, index: 1, name: "str_length_\(suffix)"),
                  let byteCount = bindings.buildExtractValue(builder, aggregate: aggregate, index: 2, name: "str_bytes_\(suffix)"),
                  let hash = bindings.buildExtractValue(builder, aggregate: aggregate, index: 3, name: "str_hash_\(suffix)")
            else {
                return nil
            }
            return [data, length, byteCount, hash]
        }

        func bridgeStringAggregateToRuntimeRaw(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let typeLowering,
                  let fields = stringAggregateFields(value, suffix: "\(suffix)_to_raw"),
                  let bridgeFunction = declareExternalFunction(
                      named: "kk_string_from_flat",
                      parameterTypes: [
                          typeLowering.dataPointerType,
                          int64Type,
                          int64Type,
                          int64Type,
                      ],
                      returnType: int64Type
                  )
            else {
                return nil
            }
            return bindings.buildCall(
                builder,
                functionType: bridgeFunction.type,
                callee: bridgeFunction.value,
                arguments: fields,
                name: "string_raw_\(suffix)"
            ).flatMap { raw in
                // String? uses null data in aggregate form and the runtime null
                // sentinel at erased/raw boundaries.
                guard let nullData = bindings.constPointerNull(typeLowering.dataPointerType),
                      let isNull = bindings.buildICmpEqual(
                          builder,
                          lhs: fields[0],
                          rhs: nullData,
                          name: "string_raw_isnull_\(suffix)"
                      ),
                      let sentinel = bindings.constInt(int64Type, value: UInt64(bitPattern: Int64.min), signExtend: true)
                else {
                    return raw
                }
                return bindings.buildSelect(
                    builder,
                    condition: isNull,
                    thenValue: sentinel,
                    elseValue: raw,
                    name: "string_raw_nullable_\(suffix)"
                ) ?? raw
            }
        }

        func bridgeRuntimeRawToStringAggregate(
            _ raw: LLVMCAPIBindings.LLVMValueRef,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef? {
            guard let typeLowering,
                  let lengthSlot = allocateI64Slot(name: "string_bridge_length_\(suffix)"),
                  let byteCountSlot = allocateI64Slot(name: "string_bridge_bytes_\(suffix)"),
                  let hashSlot = allocateI64Slot(name: "string_bridge_hash_\(suffix)"),
                  let bridgeFunction = declareExternalFunction(
                      named: "kk_string_to_flat",
                      parameterTypes: [
                          int64Type,
                          outThrownPointerType,
                          outThrownPointerType,
                          outThrownPointerType,
                      ],
                      returnType: typeLowering.dataPointerType
                  ),
                  let data = bindings.buildCall(
                      builder,
                      functionType: bridgeFunction.type,
                      callee: bridgeFunction.value,
                      arguments: [raw, lengthSlot, byteCountSlot, hashSlot],
                      name: "string_bridge_data_\(suffix)"
                  ),
                  let length = bindings.buildLoad(
                      builder,
                      type: int64Type,
                      pointer: lengthSlot,
                      name: "string_bridge_length_val_\(suffix)"
                  ),
                  let byteCount = bindings.buildLoad(
                      builder,
                      type: int64Type,
                      pointer: byteCountSlot,
                      name: "string_bridge_bytes_val_\(suffix)"
                  ),
                  let hash = bindings.buildLoad(
                      builder,
                      type: int64Type,
                      pointer: hashSlot,
                      name: "string_bridge_hash_val_\(suffix)"
                  )
            else {
                return nil
            }
            return buildStringAggregate(
                builder: builder,
                lowering: typeLowering,
                data: data,
                length: length,
                byteCount: byteCount,
                hash: hash,
                name: "string_bridge_\(suffix)"
            )
        }

        /// BUG-B: `.length` on a String must throw `NullPointerException`
        /// when the value is *actually* null at runtime, regardless of its
        /// statically-declared non-null type -- exactly like calling any
        /// method on a null reference. This can genuinely happen: an
        /// overridden non-null `String` property read during superclass
        /// construction observes the not-yet-run subclass initializer's
        /// zero-filled backing field, which `stringAggregateFields` bridges
        /// to a null data pointer (mirroring `kk_string_to_flat`'s existing
        /// raw-handle-zero-means-null convention). `lowerBuiltinCall`'s
        /// ordinary fast path for this accessor has no way to signal a
        /// thrown exception, so this handles it here instead, before that
        /// fast path runs, with direct access to the thrown-channel
        /// plumbing (`storeOutThrownIfNonNull`, `currentBlock`) that
        /// `lowerBuiltinCall` does not have.
        func emitThrowingStringLength(
            receiverValue: LLVMCAPIBindings.LLVMValueRef,
            result: KIRExprID?,
            usesThrownChannel: Bool,
            thrownResult: KIRExprID?,
            instructionIndex: Int
        ) -> Bool {
            guard let typeLowering,
                  let fields = stringAggregateFields(receiverValue, suffix: "len_npe_\(instructionIndex)"),
                  let nullData = bindings.constPointerNull(typeLowering.dataPointerType),
                  let isNull = bindings.buildICmpEqual(
                      builder, lhs: fields[0], rhs: nullData, name: "len_npe_isnull_\(instructionIndex)"
                  ),
                  let npeFunction = declareExternalFunction(
                      named: "__kk_null_pointer_exception_new", argumentCount: 0, appendThrownChannel: false
                  ),
                  let throwBlock = bindings.appendBasicBlock(
                      context: context, function: llvmFunction.value, name: "len_npe_throw_\(instructionIndex)"
                  ),
                  let okBlock = bindings.appendBasicBlock(
                      context: context, function: llvmFunction.value, name: "len_npe_ok_\(instructionIndex)"
                  )
            else {
                return false
            }
            let continueBlock = usesThrownChannel
                ? bindings.appendBasicBlock(context: context, function: llvmFunction.value, name: "len_npe_cont_\(instructionIndex)")
                : nil
            _ = bindings.buildCondBr(builder, condition: isNull, thenBlock: throwBlock, elseBlock: okBlock)

            currentBlock = throwBlock
            bindings.positionBuilder(builder, at: throwBlock)
            let exceptionHandle = bindings.buildCall(
                builder, functionType: npeFunction.type, callee: npeFunction.value, arguments: [],
                name: "len_npe_exc_\(instructionIndex)"
            ) ?? zeroValue
            storeResult(result, zeroValue)
            if usesThrownChannel, let thrownResult, let continueBlock {
                storeResult(thrownResult, exceptionHandle)
                _ = bindings.buildBr(builder, destination: continueBlock)
            } else {
                // No enclosing catch reachable for this call within this
                // function: propagate to this function's own caller
                // immediately, matching the `nullAssert` case's pattern.
                storeOutThrownIfNonNull(exceptionHandle, suffix: "len_npe_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroReturnValue)
            }

            currentBlock = okBlock
            bindings.positionBuilder(builder, at: okBlock)
            storeResult(result, fields[1])
            if usesThrownChannel, let thrownResult {
                storeResult(thrownResult, zeroValue)
            }
            if let continueBlock {
                _ = bindings.buildBr(builder, destination: continueBlock)
                currentBlock = continueBlock
                bindings.positionBuilder(builder, at: continueBlock)
            } else {
                currentBlock = okBlock
            }
            return true
        }

        func isStringAggregateType(_ type: TypeID?) -> Bool {
            guard let type,
                  let typeSystem,
                  case .stringStruct = typeSystem.kind(of: type)
            else {
                return false
            }
            return typeLowering != nil
        }

        func isStringAggregateExpr(_ id: KIRExprID) -> Bool {
            isStringAggregateType(module.arena.exprType(id))
        }

        func isPrimitiveType(_ type: TypeID?) -> Bool {
            guard let type, let typeSystem,
                  case .primitive = typeSystem.kind(of: type)
            else { return false }
            return true
        }

        /// Raw scalar values use Int64.min as the nullable sentinel, so zero
        /// remains a valid value for nullable primitives and enum ordinals.
        /// Reference-like values still use zero as the null representation.
        func nullableRawScalarPreservesZero(_ type: TypeID?) -> Bool {
            guard let type, let typeSystem else { return false }
            switch typeSystem.kind(of: type) {
            case .primitive(_, let nullability):
                return nullability != .nonNull
            case let .classType(classType):
                return symbols?.symbol(classType.classSymbol)?.kind == .enumClass
            case .unit:
                // Safe calls returning Unit use the Int64.min sentinel for
                // null, while the valid Unit value is raw zero.
                return true
            default:
                return false
            }
        }

        func isCharSequenceRuntimeStringType(_ type: TypeID?) -> Bool {
            guard let type,
                  let typeSystem,
                  let charSequenceSymbol = typeSystem.charSequenceInterfaceSymbol
            else {
                return false
            }
            let nonNullType = typeSystem.makeNonNullable(type)
            guard case let .classType(classType) = typeSystem.kind(of: nonNullType) else {
                return false
            }
            return classType.classSymbol == charSequenceSymbol
        }

        func coerceStringValueForType(
            _ value: LLVMCAPIBindings.LLVMValueRef,
            from fromType: TypeID?,
            to toType: TypeID?,
            suffix: String
        ) -> LLVMCAPIBindings.LLVMValueRef {
            if isStringAggregateType(fromType), !isStringAggregateType(toType) {
                return bridgeStringAggregateToRuntimeRaw(value, suffix: suffix) ?? value
            }
            if !isStringAggregateType(fromType), isStringAggregateType(toType) {
                return bridgeRuntimeRawToStringAggregate(value, suffix: suffix) ?? value
            }
            return value
        }

        if usesRuntimeCallbackRawABI {
            for (index, parameter) in function.params.enumerated() where isStringAggregateType(parameter.type) {
                guard let rawValue = parameterValues[parameter.symbol] else {
                    continue
                }
                parameterValues[parameter.symbol] = bridgeRuntimeRawToStringAggregate(
                    rawValue,
                    suffix: "runtime_callback_param_\(index)"
                ) ?? rawValue
            }
        }

        func flattenedRuntimeParameterTypes(
            argumentCount: Int,
            stringArgumentPositions: [Int]
        ) -> [LLVMCAPIBindings.LLVMTypeRef?]? {
            guard let typeLowering else {
                return nil
            }
            let stringPositions = Set(stringArgumentPositions)
            var parameterTypes: [LLVMCAPIBindings.LLVMTypeRef?] = []
            for index in 0..<argumentCount {
                if stringPositions.contains(index) {
                    parameterTypes.append(contentsOf: [
                        typeLowering.dataPointerType,
                        int64Type,
                        int64Type,
                        int64Type,
                    ])
                } else {
                    parameterTypes.append(int64Type)
                }
            }
            return parameterTypes
        }

        func flattenedRuntimeArguments(
            values argumentValues: [LLVMCAPIBindings.LLVMValueRef],
            types argumentTypes: [TypeID?],
            ids argumentIDs: [KIRExprID?],
            argumentCount: Int,
            stringArgumentPositions: [Int],
            suffix: String
        ) -> [LLVMCAPIBindings.LLVMValueRef]? {
            guard argumentValues.count >= argumentCount,
                  argumentTypes.count >= argumentCount,
                  argumentIDs.count >= argumentCount
            else {
                return nil
            }
            let stringPositions = Set(stringArgumentPositions)
            var flattened: [LLVMCAPIBindings.LLVMValueRef] = []
            for index in 0..<argumentCount {
                if stringPositions.contains(index) {
                    let stringValue: LLVMCAPIBindings.LLVMValueRef
                    if let argumentID = argumentIDs[index],
                       isZeroConstant(argumentID),
                       let typeLowering,
                       let nullString = buildNullStringAggregate(
                           builder: builder,
                           lowering: typeLowering,
                           name: "string_null_flat_arg\(suffix)_\(index)"
                       )
                    {
                        stringValue = nullString
                    } else if isStringAggregateType(argumentTypes[index]) {
                        stringValue = argumentValues[index]
 …12293 tokens truncated…      outThrownPointerType,
                        ],
                        returnType: int64Type
                    ) {
                        var receiveArgs = argumentValues
                        receiveArgs.append(outValueSlot ?? nullThrownPointer)
                        _ = bindings.buildCall(
                            builder,
                            functionType: receiveFunction.type,
                            callee: receiveFunction.value,
                            arguments: receiveArgs,
                            name: "channel_receive_\(instructionIndex)"
                        )
                        if let outValueSlot,
                           let loadedValue = bindings.buildLoad(
                               builder,
                               type: int64Type,
                               pointer: outValueSlot,
                               name: "channel_recv_val_\(instructionIndex)"
                           )
                        {
                            storeResult(result, loadedValue)
                        } else {
                            storeResult(result, zeroValue)
                        }
                    } else {
                        storeResult(result, zeroValue)
                    }
                    continue
                }

                // Function-value invokes carry the callable value as their first
                // argument.  The KIR symbol is intentionally retained for
                // InlineLoweringPass to match an inline function parameter, but
                // it must not be treated as a direct callee here: doing so turns
                // a captured parameter such as `transform` into an undefined
                // external `_transform` symbol (KSP-499 compiler regression).
                let isFunctionValueInvoke = Self.functionValueInvokeCallees.contains(calleeName)
                // SequenceScope symbols retain generic parameter types for ABI
                // boxing, but their source bodies do not implement the runtime
                // builder. Honor the remapped bridge after boxing is complete.
                let isSequenceBuilderRuntimeCall = calleeName == "__kk_sequence_builder_yield"
                    || calleeName == "__kk_sequence_builder_yieldAll"
                let normalizedSymbol: SymbolID? = if !isFunctionValueInvoke,
                                                       !isSequenceBuilderRuntimeCall,
                                                       let symbol,
                                                       symbol != .invalid
                {
                    symbol
                } else {
                    SymbolID?.none
                }
                let fallbackInternal: (symbol: SymbolID, function: LLVMFunction)? = if normalizedSymbol == nil {
                    resolveUnnamedInternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        argumentTypes: argumentTypes,
                        appendThrownChannel: usesThrownChannel
                    )
                } else {
                    nil
                }
                let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
                let calleeFunction: LLVMFunction?
                let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
                let effectiveExternalName = effectiveSymbol.flatMap { symbols?.externalLinkName(for: $0) } ?? externalCalleeName
                let sourceExternalCallSignature = !isInternalCall
                    ? sourceExternalSignature(
                        for: effectiveSymbol,
                        argumentCount: argumentValues.count
                    )
                    : nil
                let shouldAppendThrownChannel = usesThrownChannel || isInternalCall || sourceExternalCallSignature != nil

                if let effectiveSymbol,
                   let internalFunction = internalFunctions[effectiveSymbol]
                {
                    calleeFunction = internalFunction
                } else if let fallbackInternal {
                    calleeFunction = fallbackInternal.function
                } else if calleeName.isEmpty {
                    calleeFunction = nil
                } else if Self.isStringLengthAggregateAccessorName(calleeName), argumentValues.count == 1 {
                    calleeFunction = declareExternalFunction(
                        named: "__kk_string_struct_get_length",
                        argumentCount: 1,
                        appendThrownChannel: false
                    )
                } else if let sourceExternalCallSignature {
                    var parameterTypes = loweredLLVMTypes(for: sourceExternalCallSignature.parameters)
                    if shouldAppendThrownChannel {
                        parameterTypes.append(outThrownPointerType)
                    }
                    calleeFunction = declareExternalFunction(
                        named: effectiveExternalName,
                        parameterTypes: parameterTypes,
                        returnType: loweredLLVMType(
                            for: sourceExternalCallSignature.returnType,
                            lowering: typeLowering,
                            defaultType: int64Type
                        )
                    )
                } else {
                    calleeFunction = declareExternalFunction(
                        named: externalCalleeName,
                        argumentCount: argumentValues.count,
                        appendThrownChannel: shouldAppendThrownChannel
                    )
                }

                guard let calleeFunction else {
                    storeResult(result, nil)
                    continue
                }

                var callArguments = argumentValues
                let internalSignature = internalSignature(for: effectiveSymbol)
                let typedSignature = isInternalCall ? internalSignature : sourceExternalCallSignature
                let callVarargFlags: [Bool] = effectiveSymbol.flatMap {
                    symbols?.functionSignature(for: $0)?.valueParameterIsVararg
                } ?? []
                let callReceiverOffset: Int = effectiveSymbol.flatMap {
                    symbols?.functionSignature(for: $0)?.receiverType == nil ? 0 : 1
                } ?? 0
                let isRuntimeCallbackRawABIInternalCall = isInternalCall
                    && effectiveSymbol.map { runtimeCallbackRawReturnSymbols.contains($0) } == true
                if let parameterTypes = typedSignature?.parameters {
                    callArguments = zip(argumentValues, parameterTypes).enumerated().map { index, pair in
                        let (argumentValue, parameterType) = pair
                        let argumentType = argumentTypes.indices.contains(index) ? argumentTypes[index] : nil
                        let varargIndex = index - callReceiverOffset
                        if callVarargFlags.indices.contains(varargIndex),
                           callVarargFlags[varargIndex]
                        {
                            // A normalized vararg is carried as an erased array/list
                            // handle even though metadata records its element type.
                            return argumentValue
                        }
                        if isRuntimeCallbackRawABIInternalCall {
                            guard isStringAggregateType(argumentType) else {
                                return argumentValue
                            }
                            return bridgeStringAggregateToRuntimeRaw(
                                argumentValue,
                                suffix: "\(instructionIndex)_runtime_callback_arg\(index)"
                            ) ?? argumentValue
                        }
                        if isStringAggregateType(argumentType), !isStringAggregateType(parameterType) {
                            return bridgeStringAggregateToRuntimeRaw(
                                argumentValue,
                                suffix: "\(instructionIndex)_internal_arg\(index)"
                            ) ?? argumentValue
                        }
                        if !isStringAggregateType(argumentType), isStringAggregateType(parameterType) {
                            if arguments.indices.contains(index),
                               isZeroConstant(arguments[index]),
                               let typeLowering,
                               let nullString = buildNullStringAggregate(
                                   builder: builder,
                                   lowering: typeLowering,
                                   name: "string_null_internal_arg\(instructionIndex)_\(index)"
                               )
                            {
                                return nullString
                            }
                            return bridgeRuntimeRawToStringAggregate(
                                argumentValue,
                                suffix: "\(instructionIndex)_internal_arg\(index)"
                            ) ?? argumentValue
                        }
                        return argumentValue
                    }
                }
                let shouldBridgeExternalStringABI = !isInternalCall && sourceExternalCallSignature == nil && typeLowering != nil
                if shouldBridgeExternalStringABI {
                    callArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        guard isStringAggregateType(argumentType) else {
                            return argumentValue
                        }
                        return bridgeStringAggregateToRuntimeRaw(
                            argumentValue,
                            suffix: "\(instructionIndex)_arg\(index)"
                        ) ?? argumentValue
                    }
                }
                var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
                if shouldAppendThrownChannel {
                    if usesThrownChannel {
                        let thrownSlot = buildEntrySlot(name: "thrown_slot_\(instructionIndex)")
                        if let thrownSlot {
                            _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                            callArguments.append(thrownSlot)
                            thrownSlotPointer = thrownSlot
                        } else {
                            callArguments.append(nullThrownPointer)
                        }
                    } else {
                        callArguments.append(nullThrownPointer)
                    }
                }

                let callValue = bindings.buildCall(
                    builder,
                    functionType: calleeFunction.type,
                    callee: calleeFunction.value,
                    arguments: callArguments,
                    name: "call_\(instructionIndex)"
                )
                if let result, let callValue {
                    rawResultValues[result.rawValue] = callValue
                }
                let storedCallValue: LLVMCAPIBindings.LLVMValueRef?
                if isInternalCall,
                   let effectiveSymbol,
                   runtimeCallbackRawReturnSymbols.contains(effectiveSymbol),
                   let result,
                   isStringAggregateExpr(result),
                   let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_runtime_callback_result"
                    ) ?? callValue
                } else if isInternalCall,
                          let effectiveSymbol,
                          runtimeCallbackRawReturnSymbols.contains(effectiveSymbol)
                {
                    storedCallValue = callValue
                } else if isInternalCall,
                   let result,
                   let returnType = internalSignature?.returnType,
                   isStringAggregateType(returnType),
                   !isStringAggregateExpr(result),
                   let callValue
                {
                    storedCallValue = bridgeStringAggregateToRuntimeRaw(
                        callValue,
                        suffix: "\(instructionIndex)_internal_result"
                    ) ?? callValue
                } else if isInternalCall,
                          let result,
                          let returnType = internalSignature?.returnType,
                          !isStringAggregateType(returnType),
                          isStringAggregateExpr(result),
                          let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_internal_result"
                    ) ?? callValue
                } else if sourceExternalCallSignature != nil,
                          let result,
                          let returnType = sourceExternalCallSignature?.returnType,
                          isStringAggregateType(returnType),
                          !isStringAggregateExpr(result),
                          let callValue
                {
                    storedCallValue = bridgeStringAggregateToRuntimeRaw(
                        callValue,
                        suffix: "\(instructionIndex)_source_external_result"
                    ) ?? callValue
                } else if sourceExternalCallSignature != nil,
                          let result,
                          let returnType = sourceExternalCallSignature?.returnType,
                          !isStringAggregateType(returnType),
                          isStringAggregateExpr(result),
                          let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_source_external_result"
                    ) ?? callValue
                } else if shouldBridgeExternalStringABI,
                   let result,
                   isStringAggregateExpr(result),
                   let callValue
                {
                    storedCallValue = bridgeRuntimeRawToStringAggregate(
                        callValue,
                        suffix: "\(instructionIndex)_result"
                    ) ?? callValue
                } else {
                    storedCallValue = callValue
                }
                storeResult(result, storedCallValue)
                if calleeName == "kk_coroutine_continuation_new",
                   let coroutineRegisterRootFunction
                {
                    _ = bindings.buildCall(
                        builder,
                        functionType: coroutineRegisterRootFunction.type,
                        callee: coroutineRegisterRootFunction.value,
                        arguments: [callValue ?? zeroValue],
                        name: "coroutine_root_register_\(instructionIndex)"
                    )
                }
                if calleeName == "kk_coroutine_state_exit",
                   let coroutineUnregisterRootFunction
                {
                    _ = bindings.buildCall(
                        builder,
                        functionType: coroutineUnregisterRootFunction.type,
                        callee: coroutineUnregisterRootFunction.value,
                        arguments: [argumentValues.first ?? zeroValue],
                        name: "coroutine_root_unregister_\(instructionIndex)"
                    )
                }
                if usesThrownChannel,
                   let thrownSlotPointer,
                   let thrownValue = bindings.buildLoad(
                       builder,
                       type: int64Type,
                       pointer: thrownSlotPointer,
                       name: "thrown_val_\(instructionIndex)"
                   )
                {
                    if let thrownResult {
                        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                            _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                        } else {
                            storeResult(thrownResult, thrownValue)
                        }
                    } else if let hasThrown = buildThrownSlotCondition(
                        from: thrownValue,
                        name: "has_thrown_\(instructionIndex)"
                    ),
                        let thrownBlock = bindings.appendBasicBlock(
                            context: context,
                            function: llvmFunction.value,
                            name: "thrown_\(instructionIndex)"
                        ),
                        let continueBlock = bindings.appendBasicBlock(
                            context: context,
                            function: llvmFunction.value,
                            name: "call_cont_\(instructionIndex)"
                        )
                    {
                        _ = bindings.buildCondBr(
                            builder,
                            condition: hasThrown,
                            thenBlock: thrownBlock,
                            elseBlock: continueBlock
                        )

                        bindings.positionBuilder(builder, at: thrownBlock)
                        storeOutThrownIfNonNull(thrownValue, suffix: "throw_\(instructionIndex)")
                        _ = bindings.buildRet(builder, value: zeroReturnValue)

                        currentBlock = continueBlock
                        bindings.positionBuilder(builder, at: continueBlock)
                    }
                }

            case let .virtualCall(symbol, callee, receiver, arguments, result, usesThrownChannel, thrownResult, dispatch):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }

                let calleeName = interner.resolve(callee)
                let argumentValues = [resolveValue(receiver)] + arguments.map(resolveValue)
                let argumentTypes = [module.arena.exprType(receiver)] + arguments.map(module.arena.exprType)
                // Property getter reads dispatched through a vtable/itable slot
                // target a generated Kotlin accessor. A String-typed property
                // returns its string aggregate (the source ABI's indirect
                // result convention), not the raw pointer the generic fallback
                // declaration assumes — without this the receiver lands in the
                // callee's hidden result parameter and `this` reads garbage.
                // Decide on the declared callee signature rather than the
                // call-site result type: a generic `val value: T` accessed as
                // `Lazy<String>.value` still erases to a raw pointer return.
                // The KIR symbol is the synthetic getter accessor, so recover
                // the declared property type via the accessor encoding.
                let virtualCallDeclaredAggregateResult: Bool? = {
                    guard calleeName == "get",
                          argumentValues.count == 1,
                          typeLowering != nil
                    else {
                        return nil
                    }
                    if let symbol,
                       let property = symbols?.propertySymbol(forAccessor: symbol)
                    {
                        return isStringAggregateType(symbols?.propertyType(for: property))
                    }
                    if let signature = symbol.flatMap({ symbols?.functionSignature(for: $0) }) {
                        return isStringAggregateType(signature.returnType)
                    }
                    return nil
                }()
                let virtualCallReturnsAggregate = calleeName == "get"
                    && argumentValues.count == 1
                    && typeLowering != nil
                    && (virtualCallDeclaredAggregateResult
                        ?? isStringAggregateType(result.flatMap { module.arena.exprType($0) }))
                let isThrowableToStringVirtualCall: Bool = {
                    guard case .vtable = dispatch,
                          let symbols
                    else {
                        return false
                    }
                    let isToString = calleeName == "toString"
                        || symbol.flatMap { symbols.symbol($0) }
                            .map { interner.resolve($0.name) == "toString" } == true
                    guard isToString else {
                        return false
                    }
                    if let symbol,
                       Self.isThrowableToStringSymbol(symbol, interner: interner, symbols: symbols)
                    {
                        return true
                    }
                    guard let typeSystem else {
                        return false
                    }
                    return Self.isThrowableType(
                        module.arena.exprType(receiver),
                        typeSystem: typeSystem,
                        interner: interner,
                        symbols: symbols
                    )
                }()
                let externalCalleeName = Self.runtimePrimitiveAlias(
                    for: calleeName,
                    argumentCount: argumentValues.count
                ) ?? calleeName

                let normalizedSymbol: SymbolID? = if let symbol, symbol != .invalid {
                    symbol
                } else {
                    SymbolID?.none
                }
                let fallbackInternal: (symbol: SymbolID, function: LLVMFunction)? = if normalizedSymbol == nil {
                    resolveUnnamedInternalFunction(
                        named: calleeName,
                        argumentCount: argumentValues.count,
                        argumentTypes: argumentTypes,
                        appendThrownChannel: usesThrownChannel
                    )
                } else {
                    nil
                }
                let effectiveSymbol = normalizedSymbol ?? fallbackInternal?.symbol
                let isInternalCall = effectiveSymbol.flatMap { internalFunctions[$0] } != nil
                let effectiveExternalName = effectiveSymbol.flatMap { symbols?.externalLinkName(for: $0) } ?? externalCalleeName
                let sourceExternalCallSignature = !isInternalCall
                    ? sourceExternalSignature(
                        for: effectiveSymbol,
                        argumentCount: argumentValues.count
                    )
                    : nil
                let virtualSourceCallSignature: (parameters: [TypeID], returnType: TypeID)? = {
                    guard !isInternalCall,
                          let effectiveSymbol,
                          let symbols,
                          let signature = symbols.functionSignature(for: effectiveSymbol),
                          let linkName = symbols.externalLinkName(for: effectiveSymbol),
                          linkName.hasPrefix("kk_fn_"),
                          (
                              isStringAggregateType(signature.returnType)
                                  || [signature.receiverType].compactMap { $0 }.contains(where: isStringAggregateType)
                                  || signature.parameterTypes.contains(where: isStringAggregateType)
                          )
                    else {
                        return nil
                    }
                    let parameters = [signature.receiverType].compactMap { $0 } + signature.parameterTypes
                    guard parameters.count == argumentValues.count else {
                        return nil
                    }
                    return (parameters: parameters, returnType: signature.returnType)
                }()
                // An interface declaration imported from a library is not in the
                // consumer's internal function table, but its itable entries point
                // at generated Kotlin functions, which always carry the hidden
                // thrown channel. Keep the indirect function type consistent with
                // that source-backed ABI (KSP-712).
                let shouldAppendThrownChannel = usesThrownChannel
                    || isInternalCall
                    || sourceExternalCallSignature != nil
                    || virtualSourceCallSignature != nil
                let sourceExternalFunction: LLVMFunction? = if let sourceCallSignature =
                    virtualSourceCallSignature ?? sourceExternalCallSignature
                {
                    {
                        var parameterTypes = loweredLLVMTypes(for: sourceCallSignature.parameters)
                        if shouldAppendThrownChannel {
                            parameterTypes.append(outThrownPointerType)
                        }
                        return declareExternalFunction(
                            named: effectiveExternalName,
                            parameterTypes: parameterTypes,
                            returnType: loweredLLVMType(
                                for: sourceCallSignature.returnType,
                                lowering: typeLowering,
                                defaultType: int64Type
                            )
                        )
                    }()
                } else {
                    nil
                }

                // Itable slots carry the interface member's signature: a
                // String-returning member is invoked through the flat aggregate
                // convention on every call path (real implementations register
                // flat getters, bridged by itableBridgeSymbolForMethod when the
                // impl ABI differs). The unnamed `__v` fallback must therefore
                // declare the aggregate return for itable String results rather
                // than the raw Int handle used by runtime-registered members,
                // which keeps the indirect-call ABI independent of whether the
                // getter's KIRFunction happens to be emitted in this module.
                //
                // The call-site result type only decides this when the
                // accessor's declared type is unavailable: a generic
                // `val value: T` erases to the raw pointer ABI even when this
                // call site reads it as `Lazy<String>.value`, so a resolved
                // non-aggregate declaration must suppress the flat path.
                let virtualItableFlatAggregateResult = if let result,
                                                          virtualCallDeclaredAggregateResult != false,
                                                          typeLowering != nil
                {
                    switch dispatch {
                    case .itable, .itableDynamic:
                        isStringAggregateExpr(result)
                    default:
                        false
                    }
                } else {
                    false
                }

                let calleeFunction: LLVMFunction? = if let effectiveSymbol,
                                                       let internalFunction = internalFunctions[effectiveSymbol]
                {
                    internalFunction
                } else if let fallbackInternal {
                    fallbackInternal.function
                } else if calleeName.isEmpty {
                    nil
                } else if Self.isStringLengthAggregateAccessorName(calleeName), argumentValues.count == 1 {
                    declareExternalFunction(
                        named: "__kk_string_struct_get_length",
                        argumentCount: 1,
                        appendThrownChannel: false
                    )
                } else if isThrowableToStringVirtualCall {
                    declareExternalFunction(
                        named: "__kk_throwable_toString",
                        argumentCount: argumentValues.count,
                        appendThrownChannel: true
                    )
                } else if sourceExternalFunction != nil {
                    sourceExternalFunction
                } else {
                    // Virtual calls go through `fptr`, so this declaration only carries
                    // the indirect-call type. Fold arity into the name: a property getter
                    // and an unrelated same-named method (e.g. "get") can share
                    // `externalCalleeName` in one body, and the plain-name cache would
                    // size both to the larger arity. The `_s` suffix marks a
                    // source-ABI aggregate return (see `virtualCallReturnsAggregate`)
                    // so it cannot alias the raw `Int`-returning shape.
                    declareExternalFunction(
                        named: "\(externalCalleeName)__v\(argumentValues.count)\(virtualCallReturnsAggregate || virtualItableFlatAggregateResult ? "_s" : "")",
                        parameterTypes: Array<LLVMCAPIBindings.LLVMTypeRef?>(
                            repeating: int64Type, count: argumentValues.count
                        ) + (shouldAppendThrownChannel ? [outThrownPointerType] : []),
                        returnType: virtualCallReturnsAggregate || virtualItableFlatAggregateResult
                            ? loweredLLVMType(
                                for: result.flatMap { module.arena.exprType($0) },
                                lowering: typeLowering,
                                defaultType: int64Type
                            )
                            : int64Type
                    )
                }

                guard let calleeFunction else {
                    storeResult(result, nil)
                    continue
                }

                let calleeKIRFunction = effectiveSymbol.flatMap { module.arena.function(for: $0) }
                let isRuntimeCallbackRawABIVirtualCall = isInternalCall
                    && effectiveSymbol.map { runtimeCallbackRawReturnSymbols.contains($0) } == true
                let shouldBridgeVirtualExternalStringABI = !isInternalCall
                    && typeLowering != nil
                    && (virtualSourceCallSignature == nil || isThrowableToStringVirtualCall)
                    && !virtualCallReturnsAggregate
                    && !virtualItableFlatAggregateResult
                var virtualCallArguments = argumentValues
                if isRuntimeCallbackRawABIVirtualCall {
                    virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        guard isStringAggregateType(argumentType) else {
                            return argumentValue
                        }
                        return bridgeStringAggregateToRuntimeRaw(
                            argumentValue,
                            suffix: "\(instructionIndex)_virtual_callback_arg\(index)"
                        ) ?? argumentValue
                    }
                } else if shouldBridgeVirtualExternalStringABI {
                    virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        guard isStringAggregateType(argumentType) else {
                            return argumentValue
                        }
                        return bridgeStringAggregateToRuntimeRaw(
                            argumentValue,
                            suffix: "\(instructionIndex)_virtual_arg\(index)"
                        ) ?? argumentValue
                    }
                } else if isInternalCall,
                          let calleeKIRFunction
                {
                    // Interface dispatch through a KIR-declared function may see a
                    // String aggregate at the call site while the erased interface
                    // parameter is a raw pointer (or vice-versa). Convert across the
                    // boundary so the looked-up function pointer receives/returns the
                    // ABI expected by its KIR signature.
                    virtualCallArguments = zip(argumentValues, argumentTypes).enumerated().map { index, pair in
                        let (argumentValue, argumentType) = pair
                        let paramType = index < calleeKIRFunction.params.count
                            ? calleeKIRFunction.params[index].type
                            : nil
                        return coerceStringValueForType(
                            argumentValue,
                            from: argumentType,
                            to: paramType,
                            suffix: "\(instructionIndex)_virtual_internal_arg\(index)"
                        )
                    }
                }

                let lookupFunction: LLVMFunction?
                var lookupArgs: [LLVMCAPIBindings.LLVMValueRef] = []
                // The receiver used for the lookup must have the same runtime
                // representation as the indirect getter call. A bundled
                // CharSequence extension may still carry a flat String
                // aggregate at this point; `virtualCallArguments` performs the
                // required boxing before the getter is invoked, while using the
                // original aggregate here makes the runtime look up a bogus
                // object address and report a missing itable entry.
                let lookupReceiver = virtualCallArguments.first ?? resolveValue(receiver)
                switch dispatch {
                case let .vtable(slot):
                    lookupFunction = declareExternalFunction(named: "kk_vtable_lookup", argumentCount: 2, appendThrownChannel: false)
                    lookupArgs = [
                        lookupReceiver,
                        bindings.constInt(int64Type, value: UInt64(slot)) ?? bindings.constInt(int64Type, value: 0)!,
                    ]
                case let .itable(interfaceSlot, methodSlot):
                    lookupFunction = declareExternalFunction(named: "kk_itable_lookup", argumentCount: 3, appendThrownChannel: false)
                    lookupArgs = [
                        lookupReceiver,
                        bindings.constInt(int64Type, value: UInt64(interfaceSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                        bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                    ]
                case let .itableDynamic(interfaceTypeID, methodSlot):
                    lookupFunction = declareExternalFunction(named: "kk_itable_lookup_dynamic", argumentCount: 3, appendThrownChannel: false)
                    lookupArgs = [
                        lookupReceiver,
                        bindings.constInt(int64Type, value: UInt64(bitPattern: interfaceTypeID)) ?? bindings.constInt(int64Type, value: 0)!,
                        bindings.constInt(int64Type, value: UInt64(methodSlot)) ?? bindings.constInt(int64Type, value: 0)!,
                    ]
                }

                guard let lookupFn = lookupFunction else { continue }
                guard let fptrRaw = bindings.buildCall(
                    builder,
                    functionType: lookupFn.type,
                    callee: lookupFn.value,
                    arguments: lookupArgs,
                    name: "lookup_raw_\(instructionIndex)"
                ) else { continue }

                // Guard against null vtable/itable lookup: if fptrRaw == 0
                // call kk_dispatch_error runtime trap instead of falling back
                // to direct dispatch (GEN-002).
                guard let isNonNull = bindings.buildICmpNotEqual(
                    builder,
                    lhs: fptrRaw,
                    rhs: zeroValue,
                    name: "lookup_nonnull_\(instructionIndex)"
                ),
                    let useVirtualBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "lookup_ok_\(instructionIndex)"
                    ),
                    let fallbackBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "lookup_fallback_\(instructionIndex)"
                    ),
                    let mergeBlock = bindings.appendBasicBlock(
                        context: context,
                        function: llvmFunction.value,
                        name: "vcall_merge_\(instructionIndex)"
                    )
                else {
                    continue
                }

                _ = bindings.buildCondBr(
                    builder,
                    condition: isNonNull,
                    thenBlock: useVirtualBlock,
                    elseBlock: fallbackBlock
                )
                // Virtual dispatch path: use the looked-up function pointer.
                bindings.positionBuilder(builder, at: useVirtualBlock)
                let functionPointerType = bindings.pointerType(calleeFunction.type)
                let fptr = bindings.buildIntToPtr(
                    builder,
                    value: fptrRaw,
                    type: functionPointerType,
                    name: "lookup_fptr_\(instructionIndex)"
                )

                var callArguments = virtualCallArguments
                var thrownSlotPointer: LLVMCAPIBindings.LLVMValueRef?
                if shouldAppendThrownChannel {
                    if usesThrownChannel {
                        let thrownSlot = buildEntrySlot(name: "vthrown_slot_\(instructionIndex)")
                        if let thrownSlot {
                            _ = bindings.buildStore(builder, value: zeroValue, pointer: thrownSlot)
                            callArguments.append(thrownSlot)
                            thrownSlotPointer = thrownSlot
                        } else {
                            callArguments.append(nullThrownPointer)
                        }
                    } else {
                        callArguments.append(nullThrownPointer)
                    }
                }

                let vCallValue = bindings.buildCall(
                    builder,
                    functionType: calleeFunction.type,
                    callee: fptr ?? calleeFunction.value,
                    arguments: callArguments,
                    name: "vcall_\(instructionIndex)"
                )
                if let result, let vCallValue {
                    rawResultValues[result.rawValue] = vCallValue
                }
                _ = bindings.buildBr(builder, destination: mergeBlock)

                // Fallback path: trap on dispatch failure (GEN-002).
                bindings.positionBuilder(builder, at: fallbackBlock)
                if let trapFn = declareExternalFunction(named: "kk_dispatch_error", argumentCount: 0, appendThrownChannel: false) {
                    _ = bindings.buildCall(builder, functionType: trapFn.type, callee: trapFn.value, arguments: [], name: "trap_\(instructionIndex)")
                }
                _ = bindings.buildUnreachable(builder)

                // Merge: use the virtual call result.
                bindings.positionBuilder(builder, at: mergeBlock)
                currentBlock = mergeBlock
                let mergedValue: LLVMCAPIBindings.LLVMValueRef
                if isRuntimeCallbackRawABIVirtualCall,
                   let result,
                   isStringAggregateExpr(result),
                   let vCallValue
                {
                    mergedValue = bridgeRuntimeRawToStringAggregate(
                        vCallValue,
                        suffix: "\(instructionIndex)_virtual_callback_result"
                    ) ?? vCallValue
                } else if isInternalCall,
                          let result,
                          let resultExprType = module.arena.exprType(result),
                          let vCallValue,
                          let calleeKIRFunction
                {
                    mergedValue = coerceStringValueForType(
                        vCallValue,
                        from: calleeKIRFunction.returnType,
                        to: resultExprType,
                        suffix: "\(instructionIndex)_virtual_internal_result"
                    )
                } else if let result,
                          let resultExprType = module.arena.exprType(result),
                          let vCallValue,
                          isStringAggregateType(resultExprType) != bindings.isAggregateStructValue(vCallValue)
                {
                    // The emitted callee ABI and the result's expected
                    // representation can disagree on string-aggregate-ness for
                    // itable or source-backed virtual calls — e.g. a flat
                    // aggregate getter result consumed as the raw i64 handle by
                    // a generic caller. Normalize by the value's actual shape.
                    if isStringAggregateType(resultExprType) {
                        mergedValue = bridgeRuntimeRawToStringAggregate(
                            vCallValue,
                            suffix: "\(instructionIndex)_virtual_result"
                        ) ?? vCallValue
                    } else {
                        mergedValue = bridgeStringAggregateToRuntimeRaw(
                            vCallValue,
                            suffix: "\(instructionIndex)_virtual_flat_result"
                        ) ?? vCallValue
                    }
                } else {
                    mergedValue = vCallValue ?? zeroValue
                }
                storeResult(result, mergedValue)

                // Handle thrown channel from virtual dispatch.
                if usesThrownChannel,
                   let thrownSlotPointer,
                   let thrownValue = bindings.buildLoad(
                       builder,
                       type: int64Type,
                       pointer: thrownSlotPointer,
                       name: "vthrown_val_\(instructionIndex)"
                   )
                {
                    if let thrownResult {
                        if let alloca = copyTargetAllocas[thrownResult.rawValue] {
                            _ = bindings.buildStore(builder, value: thrownValue, pointer: alloca)
                        } else {
                            storeResult(thrownResult, thrownValue)
                        }
                    } else if let hasThrown = buildThrownSlotCondition(
                        from: thrownValue,
                        name: "vhas_thrown_\(instructionIndex)"
                    ),
                        let thrownBlock = bindings.appendBasicBlock(
                            context: context,
                            function: llvmFunction.value,
                            name: "vthrown_\(instructionIndex)"
                        ),
                        let continueBlock = bindings.appendBasicBlock(
                            context: context,
                            function: llvmFunction.value,
                            name: "vcall_cont_\(instructionIndex)"
                        )
                    {
                        _ = bindings.buildCondBr(
                            builder,
                            condition: hasThrown,
                            thenBlock: thrownBlock,
                            elseBlock: continueBlock
                        )

                        bindings.positionBuilder(builder, at: thrownBlock)
                        storeOutThrownIfNonNull(thrownValue, suffix: "vthrow_\(instructionIndex)")
                        _ = bindings.buildRet(builder, value: zeroReturnValue)

                        currentBlock = continueBlock
                        bindings.positionBuilder(builder, at: continueBlock)
                    }
                }

            case let .jumpIfNotNull(value, target):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                let valueType = module.arena.exprType(value)
                if let valueType,
                   let typeLowering,
                   let typeSystem,
                   case .stringStruct = typeSystem.kind(of: valueType),
                   let dataPointer = bindings.buildExtractValue(
                       builder,
                       aggregate: resolved,
                       index: 0,
                       name: "jnn_string_data_\(instructionIndex)"
                   ),
                   let nullPointer = bindings.constPointerNull(typeLowering.dataPointerType),
                   let condition = bindings.buildICmpNotEqual(
                       builder,
                       lhs: dataPointer,
                       rhs: nullPointer,
                       name: "jnn_string_nonnull_\(instructionIndex)"
                   ),
                   let targetBlock = blockForLabel(target),
                   let fallthroughBlock = bindings.appendBasicBlock(
                       context: context,
                       function: llvmFunction.value,
                       name: "jnn_cont_\(instructionIndex)"
                   )
                {
                    _ = bindings.buildCondBr(builder, condition: condition, thenBlock: targetBlock, elseBlock: fallthroughBlock)
                    currentBlock = fallthroughBlock
                    bindings.positionBuilder(builder, at: fallthroughBlock)
                    continue
                }
                let nullSentinel = bindings.constInt(
                    int64Type,
                    value: UInt64(bitPattern: Int64.min),
                    signExtend: true
                ) ?? zeroValue
                let isNonZero = bindings.buildICmpNotEqual(
                    builder,
                    lhs: resolved,
                    rhs: zeroValue,
                    name: "jnn_nonzero_\(instructionIndex)"
                )
                let isNotSentinel = bindings.buildICmpNotEqual(
                    builder,
                    lhs: resolved,
                    rhs: nullSentinel,
                    name: "jnn_nonsentinel_\(instructionIndex)"
                )
                let condition: LLVMCAPIBindings.LLVMValueRef? = if nullableRawScalarPreservesZero(valueType) {
                    isNotSentinel
                } else if let isNonZero,
                          let isNotSentinel
                {
                    bindings.buildAnd(
                        builder,
                        lhs: isNonZero,
                        rhs: isNotSentinel,
                        name: "jnn_cond_\(instructionIndex)"
                    )
                } else {
                    nil
                }
                if let condition,
                   let targetBlock = blockForLabel(target),
                   let fallthroughBlock = bindings.appendBasicBlock(
                       context: context,
                       function: llvmFunction.value,
                       name: "jnn_cont_\(instructionIndex)"
                   )
                {
                    _ = bindings.buildCondBr(builder, condition: condition, thenBlock: targetBlock, elseBlock: fallthroughBlock)
                    currentBlock = fallthroughBlock
                    bindings.positionBuilder(builder, at: fallthroughBlock)
                }

            case let .copy(from, to):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                var copySource = resolveValue(from)
                let fromType = module.arena.exprType(from)
                let toType = module.arena.exprType(to)
                // If the copy target is a global symbolRef, store to the
                // LLVM global variable so the write persists across reads.
                if let targetExpr = module.arena.expr(to),
                   case let .symbolRef(targetSymbol) = targetExpr,
                   let globalPtr = globalVariables[targetSymbol]
                {
                    if isStringAggregateType(fromType) {
                        copySource = bridgeStringAggregateToRuntimeRaw(
                            copySource,
                            suffix: "copy_global_\(instructionIndex)"
                        ) ?? copySource
                    }
                    _ = bindings.buildStore(builder, value: copySource, pointer: globalPtr)
                } else {
                    if isStringAggregateType(fromType), !isStringAggregateType(toType) {
                        copySource = bridgeStringAggregateToRuntimeRaw(
                            copySource,
                            suffix: "copy_\(instructionIndex)"
                        ) ?? copySource
                    } else if !isStringAggregateType(fromType), isStringAggregateType(toType) {
                        copySource = bridgeRuntimeRawToStringAggregate(
                            copySource,
                            suffix: "copy_\(instructionIndex)"
                        ) ?? copySource
                    }
                    if let alloca = copyTargetAllocas[to.rawValue] {
                        _ = bindings.buildStore(builder, value: copySource, pointer: alloca)
                    } else {
                        storeResult(to, copySource)
                    }
                }

            case let .storeGlobal(value, symbol):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                var resolved = resolveValue(value)
                if isStringAggregateType(module.arena.exprType(value)) {
                    resolved = bridgeStringAggregateToRuntimeRaw(
                        resolved,
                        suffix: "store_global_\(instructionIndex)"
                    ) ?? resolved
                }
                if let globalPtr = globalVariables[symbol] {
                    _ = bindings.buildStore(builder, value: resolved, pointer: globalPtr)
                }

            case let .loadGlobal(result, symbol):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                if let globalPtr = globalVariables[symbol] {
                    if let loaded = bindings.buildLoad(
                        builder, type: int64Type, pointer: globalPtr,
                        name: nameCounter.nextName("load_global_")
                    ) {
                        let loadedValue = if isStringAggregateType(module.arena.exprType(result)) {
                            bridgeRuntimeRawToStringAggregate(
                                loaded,
                                suffix: "load_global_\(instructionIndex)"
                            ) ?? loaded
                        } else {
                            loaded
                        }
                        storeResult(result, loadedValue)
                    }
                } else {
                    let missingValue = if isStringAggregateType(module.arena.exprType(result)) {
                        bridgeRuntimeRawToStringAggregate(
                            zeroValue,
                            suffix: "load_global_missing_\(instructionIndex)"
                        ) ?? zeroValue
                    } else {
                        zeroValue
                    }
                    storeResult(result, missingValue)
                }

            case let .rethrow(value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolved = resolveValue(value)
                storeOutThrownIfNonNull(resolved, suffix: "rethrow_\(instructionIndex)")
                _ = bindings.buildRet(builder, value: zeroReturnValue)

            case let .returnIfEqual(lhs, rhs):
                guard !bindings.hasTerminator(currentBlock),
                      let trueBlock = bindings.appendBasicBlock(
                          context: context,
                          function: llvmFunction.value,
                          name: "ret_if_true_\(instructionIndex)"
                      ),
                      let falseBlock = bindings.appendBasicBlock(
                          context: context,
                          function: llvmFunction.value,
                          name: "ret_if_false_\(instructionIndex)"
                      )
                else {
                    continue
                }

                let (lhsValue, rhsValue) = rawComparableValues(lhs: lhs, rhs: rhs)
                let condition = bindings.buildICmpEqual(builder, lhs: lhsValue, rhs: rhsValue, name: "ret_if_cmp_\(instructionIndex)")
                _ = bindings.buildCondBr(builder, condition: condition, thenBlock: trueBlock, elseBlock: falseBlock)

                bindings.positionBuilder(builder, at: trueBlock)
                _ = bindings.buildRet(builder, value: lhsValue)

                currentBlock = falseBlock
                bindings.positionBuilder(builder, at: falseBlock)

            case .returnUnit:
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                _ = bindings.buildRet(builder, value: zeroReturnValue)

            case let .returnValue(value):
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                let resolvedReturnValue = resolveValue(value)
                let returnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
                    bridgeStringAggregateToRuntimeRaw(
                        resolvedReturnValue,
                        suffix: "return_\(instructionIndex)"
                    ) ?? resolvedReturnValue
                } else {
                    coerceStringValueForType(
                        resolvedReturnValue,
                        from: module.arena.exprType(value),
                        to: function.returnType,
                        suffix: "return_\(instructionIndex)"
                    )
                }
                _ = bindings.buildRet(builder, value: returnValue)

            case let .nonLocalReturn(value):
                // Non-local returns should have been lowered by InlineLoweringPass.
                // If one reaches codegen, it indicates a lowering bug. Emit a
                // trap in debug builds; in release builds fall back to a return
                // to avoid crashing the compiler, but the output is incorrect.
                assertionFailure("nonLocalReturn reached codegen -- InlineLoweringPass should have converted it")
                guard !bindings.hasTerminator(currentBlock) else {
                    continue
                }
                if let value {
                    let resolvedReturnValue = resolveValue(value)
                    let returnValue: LLVMCAPIBindings.LLVMValueRef = if returnsRawStringRuntimeCallback {
                        bridgeStringAggregateToRuntimeRaw(
                            resolvedReturnValue,
                            suffix: "nonlocal_return_\(instructionIndex)"
                        ) ?? resolvedReturnValue
                    } else {
                        coerceStringValueForType(
                            resolvedReturnValue,
                            from: module.arena.exprType(value),
                            to: function.returnType,
                            suffix: "nonlocal_return_\(instructionIndex)"
                        )
                    }
                    _ = bindings.buildRet(builder, value: returnValue)
                } else {
                    _ = bindings.buildRet(builder, value: zeroReturnValue)
                }
            }
        }

        if !bindings.hasTerminator(currentBlock) {
            _ = bindings.buildRet(builder, value: zeroReturnValue)
        }
    }

    /// Maximum KIR argument count per external callee name within a function body.
    /// Declarations are keyed only by name; if the first emitted call is arity-0 bootstrap noise
    /// (e.g. synthetic kotlin.math loads) and a later call passes arguments, LLVM must still
    /// declare the symbol with the maximum arity seen for declareExternalFunction.
    fileprivate static func maxKIRArgumentCountByExternalCallee(
        body: [KIRInstruction],
        interner: StringInterner
    ) -> [String: Int] {
        var maxCount: [String: Int] = [:]
        for instruction in body {
            switch instruction {
            case let .call(_, callee, arguments, _, _, _, _, _):
                let raw = interner.resolve(callee)
                guard !raw.isEmpty else { continue }
                let effective = effectiveExternalCalleeNameForArity(raw, argumentCount: arguments.count)
                maxCount[effective, default: 0] = max(maxCount[effective, default: 0], arguments.count)
            case .virtualCall:
                // Generic virtual calls use an arity-qualified declaration
                // (for example, `size__v1`) solely as the indirect-call type.
                // Folding their receiver-plus-argument count into the plain
                // external name can widen an unrelated direct runtime bridge
                // declaration such as `__kk_map_size(i64)` to four parameters.
                continue
            default:
                break
            }
        }
        return maxCount
    }

    private static func effectiveExternalCalleeNameForArity(_ calleeName: String, argumentCount: Int) -> String {
        if isStringLengthAggregateAccessorName(calleeName), argumentCount == 1 {
            "__kk_string_struct_get_length"
        } else {
            calleeName
        }
    }

    private static func isStringLengthAggregateAccessorName(_ calleeName: String) -> Bool {
        calleeName == "length"
            || calleeName == "__kk_string_struct_get_length"
            || calleeName == "kk_string_struct_get_length"
    }

    private static func runtimePrimitiveAlias(for calleeName: String, argumentCount: Int) -> String? {
        switch calleeName {
        case "and": "kk_bitwise_and"
        case "or": "kk_bitwise_or"
        case "xor": "kk_bitwise_xor"
        case "__doubleRoundToInt": "kk_double_roundToInt"
        case "__floatRoundToInt": "kk_float_roundToInt"
        case "__doubleRoundToLong": "kk_double_roundToLong"
        case "__floatRoundToLong": "kk_float_roundToLong"
        case "__assert": "kk_precondition_assert"
        case "__assertLazy": "kk_precondition_assert_lazy"
        default: nil
        }
    }
}

