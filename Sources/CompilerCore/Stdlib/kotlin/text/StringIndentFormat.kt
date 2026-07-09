package kotlin.text

// String indent and format functions migrated from Swift Runtime
// MIGRATION-TEXT-006
//
// Public APIs stay source-backed while delegating to private __kk_* bridges.
// This avoids reviving the legacy public kk_string_* synthetic/member lowering
// surface and keeps the current runtime semantics for multiline raw strings.

private external fun String.__kk_string_trimIndent(): String
private external fun String.__kk_string_trimMargin(marginPrefix: String): String
private external fun String.__kk_string_prependIndent(indent: String): String
private external fun String.__kk_string_replaceIndent(newIndent: String): String
private external fun String.__kk_string_replaceIndentByMargin(newIndent: String, marginPrefix: String): String

/**
 * Detects a common minimal indent of all the input lines, removes it from every line and also
 * removes the first and the last lines if they are blank.
 */
public fun String.trimIndent(): String =
    this.__kk_string_trimIndent()

/**
 * Trims leading whitespace characters followed by [marginPrefix] from every line of a source string
 * and removes the first and the last lines if they are blank.
 */
public fun String.trimMargin(marginPrefix: String = "|"): String =
    this.__kk_string_trimMargin(marginPrefix)

/**
 * Prepends [indent] to every line of the original string.
 */
public fun String.prependIndent(indent: String = "    "): String =
    this.__kk_string_prependIndent(indent)

/**
 * Detects indent (as in [trimIndent]), removes it, then prepends [newIndent] to every line.
 */
public fun String.replaceIndent(newIndent: String = ""): String =
    this.__kk_string_replaceIndent(newIndent)

/**
 * Trims leading whitespace followed by [marginPrefix] (as in [trimMargin]),
 * then prepends [newIndent] to every non-margin line.
 */
public fun String.replaceIndentByMargin(newIndent: String = "", marginPrefix: String = "|"): String =
    this.__kk_string_replaceIndentByMargin(newIndent, marginPrefix)
