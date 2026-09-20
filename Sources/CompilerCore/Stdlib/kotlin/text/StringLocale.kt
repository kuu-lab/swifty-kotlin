package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-717: locale-parameterized String bridges backing the case-conversion
// (StringCaseConversion.kt) and comparison (StringComparison.kt) overloads.
// Locale-aware case folding and collation stay in the runtime (ICU/Foundation).

@KsSymbolName("__kk_lowercase_locale")
internal external fun String.__kk_lowercase_locale(locale: java.util.Locale): String

@KsSymbolName("__kk_uppercase_locale")
internal external fun String.__kk_uppercase_locale(locale: java.util.Locale): String

@KsSymbolName("__kk_string_compareTo_locale")
internal external fun String.__kk_string_compareTo_locale(other: String, locale: java.util.Locale): Int
