// swiftlint:disable file_length

/// `RuntimeABISpec.regexFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    static let regexFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_regex_create_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_matches_regex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_contains_regex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_find_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_findAll_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split_regex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-TEXT-FN-105: String.toRegex(option) / String.toRegex(options)
        RuntimeABIFunctionSpec(
            name: "kk_string_toRegex_with_option_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toRegex_with_options_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toRegex_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_pattern",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-REGEX-096: Regex.options: Set<RegexOption>
        RuntimeABIFunctionSpec(
            name: "kk_regex_options",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_result_value",
            parameters: [
                RuntimeABIParameter(name: "matchResult", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_result_groupValues",
            parameters: [
                RuntimeABIParameter(name: "matchResult", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-351: Regex.replace lambda / STDLIB-350: Regex.matchEntire
        RuntimeABIFunctionSpec(
            name: "kk_regex_replace_lambda",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_matchEntire_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-480: Regex(pattern, option) constructor
        RuntimeABIFunctionSpec(
            name: "kk_regex_create_with_option_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-480: Regex(pattern, options: Set<RegexOption>) constructor
        RuntimeABIFunctionSpec(
            name: "kk_regex_create_with_options_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "optionsSetRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-480: Regex.containsMatchIn(input)
        RuntimeABIFunctionSpec(
            name: "kk_regex_containsMatchIn_flat",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // MatchResult.groups / MatchGroupCollection / MatchGroup
        RuntimeABIFunctionSpec(
            name: "kk_match_result_groups",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_get",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_get_flat",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_get_at",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_size",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_value",
            parameters: [
                RuntimeABIParameter(name: "groupRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_range",
            parameters: [
                RuntimeABIParameter(name: "groupRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        // STDLIB-REGEX-094: Regex.matches(input)
        // STDLIB-REGEX-094: Regex.fromLiteral
        // First param is the Companion object receiver (ignored at runtime).
        RuntimeABIFunctionSpec(
            name: "kk_regex_from_literal_flat",
            parameters: [
                RuntimeABIParameter(name: "companionRef", type: .intptr),
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-094: String.replaceFirst(Regex, replacement)
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceFirst_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-097: Regex.groupNames
        RuntimeABIFunctionSpec(
            name: "kk_regex_group_names",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_chunked_sequence",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_chunked_sequence_transform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed_default",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed_partial",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowedSequence_partial",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowedSequence_transform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-318: commonPrefixWith / commonSuffixWith
        RuntimeABIFunctionSpec(
            name: "kk_string_commonPrefixWith_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "otherData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "otherLength", type: .intptr),
                RuntimeABIParameter(name: "otherByteCount", type: .intptr),
                RuntimeABIParameter(name: "otherHash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_commonSuffixWith_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "otherData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "otherLength", type: .intptr),
                RuntimeABIParameter(name: "otherByteCount", type: .intptr),
                RuntimeABIParameter(name: "otherHash", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads)
        RuntimeABIFunctionSpec(
            name: "kk_string_commonPrefixWith_ignoreCase_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "otherData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "otherLength", type: .intptr),
                RuntimeABIParameter(name: "otherByteCount", type: .intptr),
                RuntimeABIParameter(name: "otherHash", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_commonSuffixWith_ignoreCase_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
                RuntimeABIParameter(name: "otherData", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "otherLength", type: .intptr),
                RuntimeABIParameter(name: "otherByteCount", type: .intptr),
                RuntimeABIParameter(name: "otherHash", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "outLength", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outByteCount", type: .nullableIntptrPointer),
                RuntimeABIParameter(name: "outHash", type: .nullableIntptrPointer),
            ],
            returnType: .nullableUInt8Pointer,
            section: "String",
            isThrowing: false
        ),
        // STDLIB-317: String.asSequence / asIterable
        RuntimeABIFunctionSpec(
            name: "kk_string_asSequence_flat",
            parameters: [
                RuntimeABIParameter(name: "data", type: .nullableConstUInt8Pointer),
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "byteCount", type: .intptr),
                RuntimeABIParameter(name: "hash", type: .intptr),
            ],
            returnType: .intptr,
            section: "String",
            isThrowing: false
        ),
    ]
}
