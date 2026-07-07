package kotlin.text

// MIGRATION-TEXT-004 / RF-STDLIB-005
//
// The public split entry points are source-backed now. Runtime-backed bridge
// members named __kk_string_split* remain synthetic while the implementation is
// still delegated to the existing Swift runtime ABI.

public fun String.split(delimiters: String): List<String> =
    this.__kk_string_split(delimiters)

public fun String.split(delimiters: String, limit: Int): List<String> =
    this.__kk_string_split_limit(delimiters, false, limit)

public fun String.split(delimiters: String, ignoreCase: Boolean): List<String> =
    this.__kk_string_split_limit(delimiters, ignoreCase, 0)

public fun String.split(delimiters: String, ignoreCase: Boolean, limit: Int): List<String> =
    this.__kk_string_split_limit(delimiters, ignoreCase, limit)

public fun String.splitToSequence(delimiter: String): Sequence<String> =
    this.__kk_string_splitToSequence(delimiter)
