package java.util

import kotlin.internal.KsSymbolName

/**
 * Source-backed shell for Java's `Locale`, used by the locale-parameterized
 * String case-conversion and comparison overloads.
 *
 * Construction is bridged to the runtime because a `Locale` wraps a
 * platform (ICU/Foundation) locale handle rather than plain stored fields.
 */
public class Locale {
    @KsSymbolName("__kk_locale_new_flat")
    public constructor(identifier: String)

    @KsSymbolName("__kk_locale_new_language_country_flat")
    public constructor(language: String, country: String)
}
