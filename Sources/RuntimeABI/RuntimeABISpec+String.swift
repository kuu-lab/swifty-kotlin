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
        stringReplaceFlatSpec,
        stringReplaceFirstFlatSpec,
        stringABI.th("kk_string_compareTo_flat", "lhsData:nullableConstUInt8Pointer lhsLength lhsByteCount lhsHash rhsData:nullableConstUInt8Pointer rhsLength rhsByteCount rhsHash"),
        stringABI.nt("__kk_string_equals_flat", "data:nullableConstUInt8Pointer length byteCount hash otherData:nullableConstUInt8Pointer otherLength otherByteCount otherHash"),
        stringABI.th("__kk_string_first_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.th("__kk_string_last_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.th("__kk_string_single_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        stringABI.nt("__kk_string_firstOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.nt("__kk_string_lastOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
        stringABI.nt("__kk_string_singleOrNull_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
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
        stringABI.th("__kk_string_get_flat", "data:nullableConstUInt8Pointer length byteCount hash indexRaw outThrown"),
        exceptionABI.th("kk_enum_valueOf_throw", "nameRaw outThrown"),
        enumABI.nt("kk_enum_make_values_array", "valuesRaw count classID"),
        enumABI.nt("kk_enum_register_values", "typeToken valuesRaw count"),
        enumABI.nt("kk_enum_values_for_token", "typeToken"),
        enumABI.nt("kk_enum_make_entries_list", "valuesRaw count"),
        enumABI.nt("kk_enum_make_entries_list_cached", "valuesRaw count classID"),
        enumABI.nt("__kk_enum_entries_from_array", "valuesRaw"),
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
        stringABI.th("__kk_bignum_divideMathContext", "lhsRaw rhsRaw precision roundingMode outThrown"),
        stringABI.th("__kk_bignum_setScale", "valueRaw scale roundingMode outThrown"),
        stringABI.nt("__kk_bignum_scale", "valueRaw"),
        stringABI.nt("__kk_bignum_toDouble", "numRaw"),
        stringABI.nt("__kk_bignum_toFloat", "numRaw"),
        stringABI.nt("__kk_bignum_toLong", "numRaw"),
        stringABI.nt("__kk_bignum_toInt", "numRaw"),
        stringABI.nt("__kk_bignum_toShort", "numRaw"),
        stringABI.nt("__kk_bignum_toByte", "numRaw"),
        stringABI.nt("__kk_string_splitToSequence", "strRaw delimRaw"),
        bridgeStringJoinToStringSpec,

        stringABI.th("__kk_string_codePointCount", "strRaw"),
        stringABI.th("__kk_string_codePointCount_from", "strRaw startIndex outThrown"),
        stringABI.th("__kk_string_codePointCount_range", "strRaw startIndex endIndex outThrown"),
        stringABI.nt("__kk_string_compareTo_member", "strRaw otherRaw"),
        stringABI.nt("__kk_string_intern", "strRaw"),
        stringABI.nt("__kk_string_plus", "receiverRaw otherRaw"),
    ]
}
