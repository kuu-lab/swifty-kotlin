package kotlin.text

// String case conversion and locale functions migrated from Swift Runtime
// MIGRATION-TEXT-005

/**
 * Returns a copy of this string converted to lower case using Unicode simple case mapping.
 *
 * Each character is converted independently via [Char.lowercaseChar]. This gives Locale.ROOT
 * semantics (no language-specific rules). For locale-sensitive conversion (e.g., Turkish
 * dotless-i: 'I' → 'ı'), use [lowercase(java.util.Locale)].
 */
public fun String.lowercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder(length)
    for (i in 0 until length) {
        sb.append(this[i].lowercaseChar())
    }
    return sb.toString()
}

/**
 * Returns a copy of this string converted to upper case using Unicode simple case mapping.
 *
 * Each character is converted independently via [Char.uppercaseChar]. This gives Locale.ROOT
 * semantics (no language-specific rules). For locale-sensitive conversion (e.g., Turkish
 * dotted-İ: 'i' → 'İ'), use [uppercase(java.util.Locale)].
 */
public fun String.uppercase(): String {
    if (isEmpty()) return this
    val sb = StringBuilder(length)
    for (i in 0 until length) {
        sb.append(this[i].uppercaseChar())
    }
    return sb.toString()
}

/**
 * Returns a copy of this string having its first letter title-cased using the rules of
 * the default locale, or the original string if it's empty or already starts with a title
 * case letter.
 *
 * Deprecated since Kotlin 1.5. Prefer [replaceFirstChar] which makes the intent explicit.
 */
@Deprecated(
    message = "Use replaceFirstChar instead.",
    replaceWith = ReplaceWith(
        "replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }",
        "java.util.Locale"
    )
)
public fun String.capitalize(): String {
    if (isEmpty()) return this
    return this[0].uppercaseChar() + substring(1)
}

/**
 * Returns a string having its first character replaced with the result of the given [transform]
 * function. If this string is empty, the result is also empty.
 *
 * Common usage:
 * - Capitalise: `"hello".replaceFirstChar { it.uppercaseChar() }` → `"Hello"`
 * - Lower-first: `"World".replaceFirstChar { it.lowercaseChar() }` → `"world"`
 *
 * Note: KSwiftK currently models the transform as `(Char) -> Char` to match the synthetic
 * stub dispatch (`kk_string_replaceFirstChar`). The upstream Kotlin stdlib signature uses
 * `(Char) -> CharSequence`; migrate this overload once RF-STDLIB-002 lands.
 */
@kotlin.internal.InlineOnly
public inline fun String.replaceFirstChar(transform: (Char) -> Char): String {
    if (isEmpty()) return this
    return transform(this[0]) + substring(1)
}

/**
 * Returns a copy of this string converted to lower case using the rules of the given [locale].
 *
 * On the KSwiftK native target, locale-sensitive conversion is provided by the Swift runtime
 * bridge (`kk_string_lowercase_locale`), which delegates to Foundation's `lowercased(with:)`.
 * This Kotlin source is the API surface declaration; actual locale dispatch is injected at the
 * IR lowering layer when RF-STDLIB-002 enables bundled source loading.
 *
 * Example where locale matters: Turkish 'I'.lowercase(Locale("tr")) → "ı" (dotless-i).
 *
 * @param locale The locale whose case rules should be applied.
 */
public fun String.lowercase(locale: java.util.Locale): String {
    // Locale-aware path: provided by kk_string_lowercase_locale at runtime.
    // Fallback below gives Locale.ROOT semantics (character-by-character mapping).
    return lowercase()
}

/**
 * Returns a copy of this string converted to upper case using the rules of the given [locale].
 *
 * On the KSwiftK native target, locale-sensitive conversion is provided by the Swift runtime
 * bridge (`kk_string_uppercase_locale`), which delegates to Foundation's `uppercased(with:)`.
 * This Kotlin source is the API surface declaration; actual locale dispatch is injected at the
 * IR lowering layer when RF-STDLIB-002 enables bundled source loading.
 *
 * Example where locale matters: Turkish 'i'.uppercase(Locale("tr")) → "İ" (dotted-İ).
 *
 * @param locale The locale whose case rules should be applied.
 */
public fun String.uppercase(locale: java.util.Locale): String {
    // Locale-aware path: provided by kk_string_uppercase_locale at runtime.
    // Fallback below gives Locale.ROOT semantics (character-by-character mapping).
    return uppercase()
}
