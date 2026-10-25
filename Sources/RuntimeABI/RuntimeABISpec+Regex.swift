private let abi = RuntimeABISectionBuilder("Regex")
private let abiString = RuntimeABISectionBuilder("String")

public extension RuntimeABISpec {
    static let regexFunctions: [RuntimeABIFunctionSpec] = [
        abi.th("__kk_regex_create_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        abi.nt("__kk_string_matches_regex_flat", "data:nullableConstUInt8Pointer length byteCount hash regex"),
        abi.nt("__kk_string_contains_regex_flat", "data:nullableConstUInt8Pointer length byteCount hash regex"),
        abi.nt("__kk_regex_find_flat", "regexRaw data:nullableConstUInt8Pointer length byteCount hash"),
        abi.nt("__kk_regex_findAll_flat", "regexRaw data:nullableConstUInt8Pointer length byteCount hash"),
        abi.th("__kk_string_replace_regex", "str regex replacement outThrown"),
        abi.nt("__kk_string_split_regex_flat", "data:nullableConstUInt8Pointer length byteCount hash regexRaw"),
        abi.th("__kk_string_toRegex_with_option_flat", "data:nullableConstUInt8Pointer length byteCount hash optionRaw outThrown"),
        abi.th("__kk_string_toRegex_with_options_flat", "data:nullableConstUInt8Pointer length byteCount hash optionsRaw outThrown"),
        abi.th("__kk_string_toRegex_flat", "data:nullableConstUInt8Pointer length byteCount hash outThrown"),
        abi.nt("__kk_regex_pattern", "regex"),
        abi.nt("__kk_regex_option_mask", "regex"),
        abi.th("__kk_regex_replace_lambda", "regexRaw strRaw fnPtr closureRaw outThrown"),
        abi.nt("__kk_regex_matchEntire_flat", "regexRaw data:nullableConstUInt8Pointer length byteCount hash"),
        abi.th("__kk_regex_create_with_option_flat", "data:nullableConstUInt8Pointer length byteCount hash optionRaw outThrown"),
        abi.th("__kk_regex_create_with_options_flat", "data:nullableConstUInt8Pointer length byteCount hash optionsSetRaw outThrown"),
        abi.nt("__kk_regex_containsMatchIn_flat", "regexRaw data:nullableConstUInt8Pointer length byteCount hash"),
        abi.nt("__kk_regex_matches_flat", "regexRaw data:nullableConstUInt8Pointer length byteCount hash"),
        abi.nt("__kk_match_result_group_count", "matchRaw"),
        abi.nt("__kk_match_result_group_value", "matchRaw index"),
        abi.nt("__kk_match_result_group_start", "matchRaw index"),
        abi.nt("__kk_match_result_group_end", "matchRaw index"),
        abi.nt("__kk_match_result_group_index_of_name", "matchRaw nameRaw"),
        abi.nt("__kk_match_result_group_index_of_name_flat", "matchRaw data:nullableConstUInt8Pointer length byteCount hash"),
        abi.nt("__kk_match_result_has_named_group", "matchRaw nameRaw"),
        // First param is the Companion object receiver (ignored at runtime).
        abi.nt("__kk_regex_from_literal_flat", "companionRef data:nullableConstUInt8Pointer length byteCount hash"),
        abi.th("__kk_string_replaceFirst_regex", "str regex replacement outThrown"),
        abiString.nt("kk_string_asSequence_flat", "data:nullableConstUInt8Pointer length byteCount hash"),
    ]
}
