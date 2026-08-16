package kotlin.text

import kotlin.internal.KsSymbolName

// Retained for compatibility with older bundled callers. Current collection
// join APIs live in kotlin.collections and do not route through this bridge.
@KsSymbolName("__kk_string_joinToString")
private external fun <T> List<T>.__kkStringJoinToString(
    separator: String,
    prefix: String,
    postfix: String
): String

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
