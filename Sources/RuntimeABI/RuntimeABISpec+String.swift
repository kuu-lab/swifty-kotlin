// swiftlint:disable file_length

private let stringABI = RuntimeABISectionBuilder("String")
private let byteArrayABI = RuntimeABISectionBuilder("ByteArray")
private let collectionsABI = RuntimeABISectionBuilder("Collections")
private let enumABI = RuntimeABISectionBuilder("Enum")
private let exceptionABI = RuntimeABISectionBuilder("Exception")

public extension RuntimeABISpec {
    static let stringFromUtf8Spec: RuntimeABIFunctionSpec = stringABI.th("kk_string_from_utf8", "ptr:constUInt8Pointer len:int32", ret: .opaquePointer)

    static let bridgeStringConcatFlatSpec: RuntimeABIFunctionSpec = stringABI.nt(
        "__kk_string_concat_flat",
        "lhsData:nullableConstUInt8Pointer lhsLength lhsByteCount lhsHash rhsData:nullableConstUInt8Pointer "
            + "rhsLength rhsByteCount rhsHash outLength:nullableIntptrPointer outByteCount:nullableIntptrPointer "
            + "outHash:nullableIntptrPointer",
        ret: .nullableUInt8Pointer
    )

    static let stringReplaceFlatSpec: RuntimeABIFunctionSpec = stringABI.th(
        "kk_string_replace_flat",
        "data:nullableConstUInt8Pointer length byteCount hash oldData:nullableConstUInt8Pointer oldLength "
            + "oldByteCount oldHash newData:nullableConstUInt8Pointer newLength newByteCount newHash "
            + "outLength:nullableIntptrPointer outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer",
        ret: .nullableUInt8Pointer
    )

    static let stringReplaceFirstFlatSpec: RuntimeABIFunctionSpec = stringABI.th(
        "kk_string_replaceFirst_flat",
        "data:nullableConstUInt8Pointer length byteCount hash oldData:nullableConstUInt8Pointer oldLength "
            + "oldByteCount oldHash newData:nullableConstUInt8Pointer newLength newByteCount newHash "
            + "outLength:nullableIntptrPointer outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer",
        ret: .nullableUInt8Pointer
    )

    static let charSequenceLengthSpec: RuntimeABIFunctionSpec = stringABI.nt("kk_char_sequence_length", "raw")

    static let bridgeStringFormatFlatSpec: RuntimeABIFunctionSpec = stringABI.th(
        "__kk_string_format_flat",
        "data:nullableConstUInt8Pointer length byteCount hash argsArrayRaw outLength:nullableIntptrPointer "
            + "outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer outThrown",
        ret: .nullableUInt8Pointer
    )

    static let bridgeStringFormatLocaleFlatSpec: RuntimeABIFunctionSpec = stringABI.th(
        "__kk_string_format_locale_flat",
        "localeRaw data:nullableConstUInt8Pointer length byteCount hash argsArrayRaw "
            + "outLength:nullableIntptrPointer outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer "
            + "outThrown",
        ret: .nullableUInt8Pointer
    )

    static let stringIfBlankFlatSpec: RuntimeABIFunctionSpec = stringABI.th(
        "kk_string_ifBlank_flat",
        "data:nullableConstUInt8Pointer length byteCount hash fnPtr closureRaw outLength:nullableIntptrPointer "
            + "outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer outThrown",
        ret: .nullableUInt8Pointer
    )

    static let stringIfEmptyFlatSpec: RuntimeABIFunctionSpec = stringABI.th(
        "kk_string_ifEmpty_flat",
        "data:nullableConstUInt8Pointer length byteCount hash fnPtr closureRaw outLength:nullableIntptrPointer "
            + "outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer outThrown",
        ret: .nullableUInt8Pointer
    )

    static let bridgeStringJoinToStringSpec: RuntimeABIFunctionSpec = stringABI.nt("__kk_string_joinToString", "listRaw separatorRaw prefixRaw postfixRaw")

    static let stringFunctions: [RuntimeABIFunctionSpec] = [
        stringABI.nt("__kk_string_literal_from_utf8", "pointer:constUInt8Pointer count"),
        stringFromUtf8Spec,
        stringABI.th("kk_string_from_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.th("kk_string_to_flat", "raw outLength:nullableIntptrPointer outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer", ret: .nullableUInt8Pointer),
        bridgeStringConcatFlatSpec,
        stringABI.th(
            "kk_string_lowercase_flat",
            "data:nullableConstUInt8Pointer length byteCount hash outLength:nullableIntptrPointer "
                + "outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer",
            ret: .nullableUInt8Pointer
        ),
        stringABI.th(
            "kk_string_uppercase_flat",
            "data:nullableConstUInt8Pointer length byteCount hash outLength:nullableIntptrPointer "
                + "outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer",
            ret: .nullableUInt8Pointer
        ),
        // KSP-1396: reversed is bundled Kotlin source (StringBasics.kt); its
        // flat ABI entry was removed.
        stringReplaceFlatSpec,
        stringReplaceFirstFlatSpec,
        // KSP-406: substring/subSequence/removeRange/replaceRange flat entries removed;
        // now bundled Kotlin source (StringSubstringSlice.kt).
        // KSP-1390: padStart/padEnd are bundled Kotlin source (StringHOF.kt);
        // their flat ABI entries were removed.
        // KSP-1394: repeat is bundled Kotlin source (StringBasics.kt); its flat
        // ABI entry was removed.
        // KSP-407: substringBefore/After/BeforeLast/AfterLast and
        // replaceBefore/After/BeforeLast/AfterLast are bundled Kotlin source
        // (StringSearchReplace.kt); their flat ABI entries were removed.
        // KSP-405: take/takeLast/drop/dropLast are bundled Kotlin source
        // (StringTakeDrop.kt); their flat ABI entries were removed.
        stringABI.th("kk_string_compareTo_flat", "lhsData:nullableConstUInt8Pointer lhsLength lhsByteCount lhsHash rhsData:nullableConstUInt8Pointer rhsLength rhsByteCount rhsHash"),
        // KSP-404: kk_string_startsWith_flat / kk_string_endsWith_flat removed;
        // startsWith/endsWith are bundled Kotlin source (StringPrefixSuffix.kt).
        // KSP-408: kk_string_contains_str_flat / kk_string_contains_ignoreCase_flat /
        // kk_string_indexOf_flat / kk_string_indexOf_from_flat /
        // kk_string_lastIndexOf_flat / kk_string_indexOf_ignoreCase_flat /
        // kk_string_indexOf_char_flat / kk_string_lastIndexOf_ignoreCase_flat /
        // kk_string_lastIndexOf_char_flat removed; contains/indexOf/lastIndexOf are
        // bundled Kotlin source (StringIndexOf.kt).
        // KSP-413: kk_string_compareToIgnoreCase_flat / kk_string_equalsIgnoreCase_flat /
        // kk_string_contentEquals_flat / kk_string_contentEquals_ignoreCase_flat removed;
        // compareTo(ignoreCase) / equals(ignoreCase) / contentEquals are bundled Kotlin
        // source (StringComparison.kt).
        stringABI.nt("__kk_string_equals_flat", "data:nullableConstUInt8Pointer length byteCount hash otherData:nullableConstUInt8Pointer otherLength otherByteCount otherHash"),
        stringABI.th("__kk_string_first_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.th("__kk_string_last_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.th("__kk_string_single_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.nt("__kk_string_firstOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.nt("__kk_string_lastOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.nt("__kk_string_singleOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        // KSP-408: kk_string_indexOfFirst_flat / kk_string_indexOfLast_flat removed;
        // indexOfFirst/indexOfLast are bundled Kotlin source (StringIndexOf.kt).
        // KSP-410: kk_string_count_flat / kk_string_any_flat / kk_string_all_flat /
        // kk_string_none_flat removed; count/any/all/none are bundled Kotlin source
        // (StringHOF.kt).
        stringABI.nt("kk_compare_any", "lhs rhs"),
        charSequenceLengthSpec,
        stringABI.th("kk_char_sequence_get", "sequenceRaw indexRaw outThrown"),
        stringABI.th("kk_char_sequence_subSequence", "sequenceRaw startIndex endIndex outThrown"),

        stringABI.th("kk_charsequence_ifBlank", "sequenceRaw fnPtr closureRaw outThrown"),
        stringABI.th("kk_charsequence_ifEmpty", "sequenceRaw fnPtr closureRaw outThrown"),
        stringABI.nt("kk_string_lowercase", "strRaw"),
        stringABI.nt("kk_string_uppercase", "strRaw"),
        stringABI.nt("__kk_locale_new_flat", "identifierData:nullableConstUInt8Pointer identifierLength identifierByteCount identifierHash"),
        stringABI.th(
            "__kk_locale_new_language_country_flat",
            "languageData:nullableConstUInt8Pointer languageLength languageByteCount languageHash "
                + "countryData:nullableConstUInt8Pointer countryLength countryByteCount countryHash",
        ),
        stringABI.th(
            "__kk_lowercase_locale_flat",
            "data:nullableConstUInt8Pointer length byteCount hash localeRaw outLength:nullableIntptrPointer "
                + "outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer",
            ret: .nullableUInt8Pointer
        ),
        stringABI.th(
            "__kk_uppercase_locale_flat",
            "data:nullableConstUInt8Pointer length byteCount hash localeRaw outLength:nullableIntptrPointer "
                + "outByteCount:nullableIntptrPointer outHash:nullableIntptrPointer",
            ret: .nullableUInt8Pointer
        ),
        stringABI.nt(
            "__kk_string_compareTo_locale_flat",
            "lhsData:nullableConstUInt8Pointer lhsLength lhsByteCount lhsHash rhsData:nullableConstUInt8Pointer "
                + "rhsLength rhsByteCount rhsHash localeRaw",
        ),
        bridgeStringFormatFlatSpec,
        bridgeStringFormatLocaleFlatSpec,
        stringABI.th("__kk_any_to_string_throwing", "value tag outThrown", ret: .opaquePointer),
        stringABI.nt("kk_any_to_string", "value tag", ret: .opaquePointer),
        stringABI.nt("kk_any_hashCode", "value tag"),
        stringABI.nt("kk_any_equals", "lhs lhsTag rhs rhsTag"),
        stringABI.nt("kk_any_member_to_string", "raw", ret: .opaquePointer),
        stringABI.nt("kk_any_member_hashCode", "raw"),
        stringABI.nt("kk_any_member_equals", "lhs rhs"),
        collectionsABI.nt("kk_structural_eq", "lhs rhs"),
        stringABI.nt("__kk_string_split", "strRaw delimRaw"),
        stringABI.nt("kk_string_split_flat", "data:nullableConstUInt8Pointer length byteCount hash delimiterData:nullableConstUInt8Pointer delimiterLength delimiterByteCount delimiterHash"),
        stringABI.nt("__kk_string_split_limit", "strRaw delimRaw ignoreCaseRaw limitRaw"),
        stringABI.th("__kk_string_toInt", "strRaw outThrown"),
        stringABI.th("__kk_string_toInt_radix", "strRaw radix outThrown"),
        stringABI.nt("__kk_string_toIntOrNull", "strRaw"),
        stringABI.th("__kk_string_toIntOrNull_radix", "strRaw radix outThrown"),
        stringABI.th("__kk_string_toUByteOrNull_radix", "strRaw radix outThrown"),
        stringABI.th("__kk_string_toUShortOrNull_radix", "strRaw radix outThrown"),
        stringABI.th("__kk_string_toUIntOrNull_radix", "strRaw radix outThrown"),
        stringABI.th("__kk_string_toULongOrNull_radix", "strRaw radix outThrown"),
        stringABI.th("__kk_string_toDouble", "strRaw outThrown"),
        stringABI.th("__kk_string_toDoubleOrNull", "strRaw"),
        stringABI.th("__kk_string_toLong", "strRaw outThrown"),
        stringABI.th("__kk_string_toLongOrNull", "strRaw"),
        stringABI.th("__kk_string_toLong_radix", "strRaw radix outThrown"),
        stringABI.th("__kk_string_toLongOrNull_radix", "strRaw radix outThrown"),
        stringABI.th("__kk_string_toFloat", "strRaw outThrown"),
        stringABI.th("__kk_string_toFloatOrNull", "strRaw"),
        stringABI.th("__kk_string_toInt_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.nt("__kk_string_toInt_radix_flat", "data:nullableConstUInt8Pointer length byteCount hash radix outThrown"),
        stringABI.nt("__kk_string_toIntOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.th("__kk_string_toIntOrNull_radix_flat", "data:nullableConstUInt8Pointer length byteCount hash radix outThrown"),
        stringABI.th("__kk_string_toUByteOrNull_radix_flat", "data:nullableConstUInt8Pointer length byteCount hash radix outThrown"),
        stringABI.th("__kk_string_toUShortOrNull_radix_flat", "data:nullableConstUInt8Pointer length byteCount hash radix outThrown"),
        stringABI.th("__kk_string_toUIntOrNull_radix_flat", "data:nullableConstUInt8Pointer length byteCount hash radix outThrown"),
        stringABI.th("__kk_string_toULongOrNull_radix_flat", "data:nullableConstUInt8Pointer length byteCount hash radix outThrown"),
        stringABI.th("__kk_string_toDouble_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.nt("__kk_string_toDoubleOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.th("__kk_string_toLong_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.nt("__kk_string_toLongOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.th("__kk_string_toFloat_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.nt("__kk_string_toFloatOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        // KSP-408: kk_string_indexOfAny_chars_flat / kk_string_indexOfAny_strings_flat /
        // kk_string_lastIndexOfAny_chars_flat / kk_string_lastIndexOfAny_strings_flat /
        // kk_string_findAnyOf_flat / kk_string_findLastAnyOf_flat removed; indexOfAny/
        // lastIndexOfAny/findAnyOf/findLastAnyOf are bundled Kotlin source (StringIndexOf.kt).
        stringABI.th("__kk_string_get_flat", "data:nullableConstUInt8Pointer length byteCount hash indexRaw outThrown"),
        exceptionABI.th("kk_enum_valueOf_throw", "nameRaw outThrown"),
        enumABI.nt("kk_enum_make_values_array", "valuesRaw count classID"),
        // KUU-1462: runtime-token dispatch for enumValues<T>() in a noinline lambda.
        enumABI.nt("kk_enum_register_values", "typeToken valuesRaw count"),
        enumABI.nt("kk_enum_values_for_token", "typeToken"),
        enumABI.nt("kk_enum_make_entries_list", "valuesRaw count"),
        // KSP-1156: cached EnumEntries shared by T.entries and enumEntries<T>().
        enumABI.nt("kk_enum_make_entries_list_cached", "valuesRaw count classID"),
        // KSP-1156: source-backed internal Array/provider overloads retain the
        // supplied Array as the EnumEntries backing view.
        enumABI.nt("__kk_enum_entries_from_array", "valuesRaw"),
        // BUG-177: boxes a values()/entries element as a genuine ordinal Int
        // (tagged with its declared name for generic Any-printing) instead of
        // a pre-baked name string. BUG-182: also carries the enum class's
        // stable nominal type ID so `is`/`as`/`KClass.isInstance` work after
        // widening to `Any`.
        enumABI.nt("kk_enum_box_ordinal", "ordinal namePtr classID"),
        enumABI.nt("__kk_enum_name", "valueRaw"),
        stringABI.nt("__kk_string_toByteArray_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.nt("__kk_string_toByteArray_charset_flat", "data:nullableConstUInt8Pointer length byteCount hash charsetTag"),
        stringABI.nt("__kk_charset_utf_8"),
        stringABI.nt("__kk_charset_iso_8859_1"),
        stringABI.nt("__kk_charset_us_ascii"),
        stringABI.nt("__kk_charset_utf_16"),
        stringABI.nt("__kk_charset_utf_16be"),
        stringABI.nt("__kk_charset_utf_16le"),
        stringABI.nt("__kk_charset_utf_32"),
        stringABI.nt("__kk_charset_utf_32be"),
        stringABI.nt("__kk_charset_utf_32le"),
        stringABI.nt("__kk_charset_name", "charsetTag"),
        stringABI.nt("__kk_string_encodeToByteArray_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.nt("__kk_string_encodeToByteArray_range_flat", "data:nullableConstUInt8Pointer length byteCount hash startIndex endIndex"),
        stringABI.nt("__kk_string_encodeToByteArray_charset_flat", "data:nullableConstUInt8Pointer length byteCount hash charsetID"),
        byteArrayABI.nt("__kk_bytearray_decodeToString", "arrRaw"),
        byteArrayABI.nt("__kk_bytearray_decodeToString_charset", "arrRaw charsetId"),
        byteArrayABI.th("__kk_bytearray_decodeToString_range", "arrRaw startIndex endIndex outThrown"),
        byteArrayABI.th("__kk_bytearray_decodeToString_range_throw", "arrRaw startIndex endIndex throwOnInvalidSequence outThrown"),
        stringABI.th("kk_char_isIdentifierIgnorable", "value"),
        // KSP-662: Bridges retained for Unicode case mapping, locale-aware
        // conversion, and digitOf table lookup after moving Char conversions to Kotlin.
        stringABI.th("__kk_char_uppercase_string", "code"),
        stringABI.th("__kk_char_lowercase_string", "code"),
        stringABI.th("__kk_char_titlecase_string", "code"),
        stringABI.th("__kk_char_uppercase_code", "code"),
        stringABI.th("__kk_char_lowercase_code", "code"),
        stringABI.th("__kk_char_titlecase_code", "code"),
        stringABI.nt("__kk_char_uppercase_locale", "code localeRaw"),
        stringABI.nt("__kk_char_lowercase_locale", "code localeRaw"),
        stringABI.th("__kk_char_digit_value", "code"),
        stringABI.th("__kk_char_numeric_value", "code"),
        stringABI.th("kk_char_isJavaIdentifierPart", "value"),
        stringABI.th("kk_char_isJavaIdentifierStart", "value"),
        stringABI.nt("kk_chararray_concatToString", "arrRaw"),
        // KSP-404: removePrefix/removeSuffix/removeSurrounding flat bridges removed;
        // implemented in bundled Kotlin source (StringPrefixSuffix.kt).

        // Source-backed declarations retain flat compatibility lowering for
        // aggregate String receivers.
        stringIfBlankFlatSpec,
        stringIfEmptyFlatSpec,
        stringABI.nt("__kk_string_toBigDecimal_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.nt("__kk_bignum_toString", "numRaw"),
        stringABI.nt("__kk_bignum_compareTo", "lhsRaw rhsRaw"),
        stringABI.th("__kk_bignum_add", "lhsRaw rhsRaw outThrown"),
        stringABI.th("__kk_bignum_subtract", "lhsRaw rhsRaw outThrown"),
        stringABI.th("__kk_bignum_multiply", "lhsRaw rhsRaw outThrown"),
        stringABI.th("__kk_bignum_divide", "lhsRaw rhsRaw outThrown"),
        stringABI.th("__kk_bignum_divideAtScale", "lhsRaw rhsRaw scale roundingMode outThrown"),
        stringABI.th("__kk_bignum_setScale", "valueRaw scale roundingMode outThrown"),
        stringABI.nt("__kk_bignum_scale", "valueRaw"),
        stringABI.nt("__kk_bignum_toDouble", "numRaw"),
        stringABI.nt("__kk_bignum_toFloat", "numRaw"),
        stringABI.nt("__kk_bignum_toLong", "numRaw"),
        stringABI.nt("__kk_bignum_toInt", "numRaw"),
        stringABI.nt("__kk_bignum_toShort", "numRaw"),
        stringABI.nt("__kk_bignum_toByte", "numRaw"),
        // KSP-410: map/mapIndexed/mapNotNull/firstNotNullOf(OrNull)/
        // filterIndexed/onEachIndexed/reduce family are bundled Kotlin source
        // (StringHOF.kt); their flat ABI entries were removed.
        // KSP-405: takeWhile/takeLastWhile/dropWhile are bundled Kotlin source
        // (StringTakeDrop.kt); their flat ABI entries were removed.
        stringABI.nt("__kk_string_splitToSequence", "strRaw delimRaw"),
        bridgeStringJoinToStringSpec,
        // MIGRATION-TEXT-006: Internal bridge functions for Kotlin stdlib source

        stringABI.th("__kk_string_codePointCount", "strRaw"),
        stringABI.th("__kk_string_codePointCount_from", "strRaw startIndex outThrown"),
        stringABI.th("__kk_string_codePointCount_range", "strRaw startIndex endIndex outThrown"),
        stringABI.nt("__kk_string_compareTo_member", "strRaw otherRaw"),
        stringABI.nt("__kk_string_intern", "strRaw"),
        stringABI.nt("__kk_string_plus", "receiverRaw otherRaw"),
        // KSP-406: replaceRange_indices/slice_iterable/slice_range removed;
        // now bundled Kotlin source (StringSubstringSlice.kt).
    ]
}
