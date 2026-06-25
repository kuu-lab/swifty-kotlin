/// Core string functions. Sub-arrays split into companion files:
/// `+Char.swift`, `+Locale.swift`, `+StringParsing.swift`,
/// `+StringSearch.swift`, `+StringHOF.swift`.
public extension RuntimeABISpec {
    static let stringCoreFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_from_utf8",
            parameters: [
                RuntimeABIParameter(name: "ptr", type: .constUInt8Pointer),
                RuntimeABIParameter(name: "len", type: .int32),
            ],
            returnType: .opaquePointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_concat",
            parameters: [
                RuntimeABIParameter(name: "a", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "b", type: .nullableOpaquePointer),
            ],
            returnType: .opaquePointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_plus",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo",
            parameters: [
                RuntimeABIParameter(name: "a", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "b", type: .nullableOpaquePointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compare_any",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_length",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trim",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trim_predicate",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lowercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_uppercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_capitalize",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimMargin_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimMargin",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "marginPrefixRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceIndentByMargin",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "newIndentRaw", type: .intptr),
                RuntimeABIParameter(name: "marginPrefixRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_format",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNullOrEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNullOrBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_startsWith",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_endsWith",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_contains_str",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-012: CharSequence.contains(other, ignoreCase)
        RuntimeABIFunctionSpec(
            name: "kk_string_contains_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldCharRaw", type: .intptr),
                RuntimeABIParameter(name: "newCharRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_char_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldCharRaw", type: .intptr),
                RuntimeABIParameter(name: "newCharRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceFirst",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceAfter",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceAfter_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceAfterLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceAfterLast_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceBefore",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceBefore_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceBeforeLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceBeforeLast_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_to_string",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_hashCode",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_equals",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "lhsTag", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "rhsTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_member_to_string",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_member_hashCode",
            parameters: [
                RuntimeABIParameter(name: "raw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_member_equals",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_structural_eq",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collections",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceRange",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeRange",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startRaw", type: .intptr),
                RuntimeABIParameter(name: "endRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeRange_range",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_substring",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startRaw", type: .intptr),
                RuntimeABIParameter(name: "endRaw", type: .intptr),
                RuntimeABIParameter(name: "hasEndRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-010: CharSequence.codePointCount
        RuntimeABIFunctionSpec(
            name: "kk_string_codePointCount",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_codePointCount_from",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_codePointCount_range",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split_limit",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "limitRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-140: String.get
        RuntimeABIFunctionSpec(
            name: "kk_string_get",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "indexRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-141: String.compareTo
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo_member",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_compareToIgnoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_equals",
            parameters: [
                RuntimeABIParameter(name: "aRaw", type: .intptr),
                RuntimeABIParameter(name: "bRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_enum_valueOf_throw",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        // STDLIB-171: enumValues<T>() / T.values() — returns Array<T>
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_values_array",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
        // ENUM-002: T.entries — returns EnumEntries<T> (List)
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_entries_list",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum",
            isThrowing: false
        ),
        // STDLIB-143: String.lines
        RuntimeABIFunctionSpec(
            name: "kk_string_lines",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-666: String.lineSequence
        RuntimeABIFunctionSpec(
            name: "kk_string_lineSequence",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-144: String.trimStart/trimEnd
        RuntimeABIFunctionSpec(
            name: "kk_string_trimStart",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimStart_predicate",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimEnd",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimEnd_predicate",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-145: String.toByteArray
        RuntimeABIFunctionSpec(
            name: "kk_string_toByteArray",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-581: String.toByteArray(charset: Charset)
        RuntimeABIFunctionSpec(
            name: "kk_string_toByteArray_charset",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_8",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_iso_8859_1",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_us_ascii",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_16",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_16be",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_16le",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_32",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_32be",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_32le",
            parameters: [],
            returnType: .intptr,
            section: "String",
            isThrowing: false,
        ),
        // STDLIB-573: String.encodeToByteArray
        RuntimeABIFunctionSpec(
            name: "kk_string_encodeToByteArray",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
        RuntimeABIFunctionSpec(
            name: "kk_string_encodeToByteArray_range",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-573: String.encodeToByteArray(charset)
        RuntimeABIFunctionSpec(
            name: "kk_string_encodeToByteArray_charset",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetID", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-574: ByteArray.decodeToString
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        // STDLIB-574: ByteArray.decodeToString(charset)
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString_charset",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetId", type: .intptr),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        // STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex, ...)
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString_range",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString_range_throw",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "throwOnInvalidSequence", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toList",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-104: CharSequence.toMutableList() — MutableList<Char>
        RuntimeABIFunctionSpec(
            name: "kk_string_toMutableList",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toCharArray",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-109: String.toTypedArray() — Array<Char>
        RuntimeABIFunctionSpec(
            name: "kk_string_toTypedArray",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-094: CharSequence.toCollection(destination)
        RuntimeABIFunctionSpec(
            name: "kk_string_toCollection",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "destRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-108: CharSequence.toSortedSet()
        RuntimeABIFunctionSpec(
            name: "kk_string_toSortedSet",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-640: CharArray.concatToString()
        RuntimeABIFunctionSpec(
            name: "kk_chararray_concatToString",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-317: String.asIterable() — lazy Iterable<Char>
        RuntimeABIFunctionSpec(
            name: "kk_string_asIterable",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-115: CharSequence.withIndex() — Iterable<IndexedValue<Char>>
        RuntimeABIFunctionSpec(
            name: "kk_string_withIndex",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterable_toList",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterable_iterator",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterator",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_take",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_drop",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_takeLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_dropLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-185
        RuntimeABIFunctionSpec(
            name: "kk_string_removePrefix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeSuffix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeSurrounding",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeSurrounding_pair",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-191
        RuntimeABIFunctionSpec(
            name: "kk_string_prependIndent_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_prependIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "indentRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceIndent_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "newIndentRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-192
        RuntimeABIFunctionSpec(
            name: "kk_string_equalsIgnoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-190
        RuntimeABIFunctionSpec(
            name: "kk_string_first",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_last",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_single",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-044
        RuntimeABIFunctionSpec(
            name: "kk_string_random",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_random_random",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-187
        RuntimeABIFunctionSpec(
            name: "kk_string_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNotEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNotBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_ifBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_ifEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-186 / STDLIB-TEXT-FN-076: String.substringBefore(delimiter, missingDelimiterValue)
        RuntimeABIFunctionSpec(
            name: "kk_string_substringBefore",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toBigIntegerOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_splitToSequence",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_joinToString",
            parameters: [
                RuntimeABIParameter(name: "strListRaw", type: .intptr),
                RuntimeABIParameter(name: "separatorRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "postfixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-FN-077: String.substringBeforeLast(delimiter, missingDelimiterValue)
        RuntimeABIFunctionSpec(
            name: "kk_string_substringBeforeLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-075: String.substringAfterLast(delimiter, missingDelimiterValue)
        RuntimeABIFunctionSpec(
            name: "kk_string_substringAfterLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
                RuntimeABIParameter(name: "missingDelimiterValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-534: String?.orEmpty()
        RuntimeABIFunctionSpec(
            name: "kk_string_orEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-116: CharSequence.zip(other) / zip(other, transform)
        RuntimeABIFunctionSpec(
            name: "kk_string_zip",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_zipTransform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // MIGRATION-TEXT-002: Internal bridge functions for Kotlin stdlib source
        RuntimeABIFunctionSpec(
            name: "__string_replace",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_replace_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_replace_char",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldCharRaw", type: .intptr),
                RuntimeABIParameter(name: "newCharRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_replace_char_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldCharRaw", type: .intptr),
                RuntimeABIParameter(name: "newCharRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_replaceFirst",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_replaceRange",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_removeRange",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startRaw", type: .intptr),
                RuntimeABIParameter(name: "endRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_removeRange_range",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_removePrefix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_removeSuffix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_removeSurrounding",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_removeSurrounding_pair",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // MIGRATION-TEXT-005: Bridge functions for case conversion
        RuntimeABIFunctionSpec(
            name: "__string_lowercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_uppercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_lowercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_uppercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // MIGRATION-TEXT-006: Internal bridge functions for Kotlin stdlib source
        RuntimeABIFunctionSpec(
            name: "__string_trimIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_trimMargin",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "marginPrefixRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_prependIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "indentRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_replaceIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "newIndentRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_replaceIndentByMargin",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "newIndentRaw", type: .intptr),
                RuntimeABIParameter(name: "marginPrefixRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "__string_format",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
    ]

    static let stringFunctions: [RuntimeABIFunctionSpec] = ([
        stringCoreFunctions,
        charClassificationFunctions,
        localeFunctions,
        stringParsingFunctions,
        stringSearchFunctions,
        stringHOFFunctions,
    ] as [[RuntimeABIFunctionSpec]]).flatMap { $0 }
}
