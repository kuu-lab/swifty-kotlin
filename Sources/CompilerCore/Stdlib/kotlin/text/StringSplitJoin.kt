package kotlin.text

// MIGRATION-TEXT-004 / RF-STDLIB-005
// Public split APIs are now source-backed. Runtime fast paths are retained as
// private __kk_* bridges so public kk_string_split* symbols disappear from
// compiler synthetic stubs and member-call lowering.

public fun String.split(delimiter: String): List<String> =
    this.__kk_string_split(delimiter)

public fun String.split(delimiter: String, limit: Int): List<String> =
    this.__kk_string_split_limit(delimiter, false, limit)

public fun String.split(delimiter: String, ignoreCase: Boolean): List<String> =
    this.__kk_string_split_limit(delimiter, ignoreCase, 0)

public fun String.split(delimiter: String, ignoreCase: Boolean, limit: Int): List<String> =
    this.__kk_string_split_limit(delimiter, ignoreCase, limit)

public fun String.splitToSequence(delimiter: String): Sequence<String> =
    this.__kk_string_splitToSequence(delimiter)

public fun <T> List<T>.joinToString(
    separator: String = ", ",
    prefix: String = "",
    postfix: String = ""
): String =
    this.__kk_string_joinToString(separator, prefix, postfix)
