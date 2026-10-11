import RuntimeABI
import CompilerCore

extension NativeEmitter {
    struct FlatStringReturnCallSpec {
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

    struct FlatScalarReturnCallSpec {
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

    static let flatStringReturnCallSpecs: [String: FlatStringReturnCallSpec] = {
        var specs: [String: FlatStringReturnCallSpec] = [
            "kk_string_to_flat": FlatStringReturnCallSpec(
                flatName: "kk_string_to_flat",
                stringArgumentCount: 0,
                extraArgumentCount: 1,
                canThrow: false
            ),
            "__kk_locale_toString_flat": FlatStringReturnCallSpec(
                flatName: "__kk_locale_toString_flat",
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
                canThrow: true
            ),
            "__kk_string_format_locale_flat": FlatStringReturnCallSpec(
                flatName: "__kk_string_format_locale_flat",
                stringArgumentCount: 1,
                extraArgumentCount: 2,
                stringArgumentPositions: [1],
                canThrow: true
            ),
        ]
        for spec in Array(specs.values)
        where specs[spec.flatName] == nil {
            specs[spec.flatName] = spec
        }
        return specs
    }()

    static let flatScalarReturnCallSpecs: [String: FlatScalarReturnCallSpec] = {
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
}
