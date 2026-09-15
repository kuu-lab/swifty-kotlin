package kotlin.text

import kotlin.internal.KsSymbolName

// KSP-717 residual: keep platform formatting and the runtime's Any? boxing
// policy behind private source-level bridges.  The public format/concat/plus
// declarations are bundled Kotlin, so they no longer need synthetic Sema
// registrations.

@KsSymbolName("__kk_string_format_flat")
private external fun String.__kkStringFormat(args: List<Any?>): String

@KsSymbolName("__kk_string_format_flat")
private external fun __kkStringFormatCompanion(format: String, args: List<Any?>): String

@KsSymbolName("__kk_string_format_locale_flat")
private external fun __kkStringFormatLocaleCompanion(
    locale: java.util.Locale?,
    format: String,
    args: List<Any?>
): String

@KsSymbolName("__kk_string_case_insensitive_order")
private external fun __kkStringCaseInsensitiveOrder(): Comparator<String>

@KsSymbolName("__kk_string_concat_flat")
private external fun String.__kkStringConcat(other: String): String

@KsSymbolName("__kk_string_plus")
private external fun __kkStringPlus(receiver: String?, other: Any?): String

public fun String.format(vararg args: Any?): String = __kkStringFormat(args)

public fun String.Companion.format(format: String, vararg args: Any?): String =
    __kkStringFormatCompanion(format, args)

public fun String.Companion.format(
    locale: java.util.Locale?,
    format: String,
    vararg args: Any?
): String = __kkStringFormatLocaleCompanion(locale, format, args)

public val String.Companion.CASE_INSENSITIVE_ORDER: Comparator<String>
    get() = __kkStringCaseInsensitiveOrder()

public fun String.concat(str: String): String = __kkStringConcat(str)

public operator fun String?.plus(other: Any?): String = __kkStringPlus(this, other)
