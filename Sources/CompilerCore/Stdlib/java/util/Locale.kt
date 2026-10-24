package java.util

import kotlin.internal.KsSymbolName

/**
 * A locale backed by the runtime's platform locale handle.
 */
public class Locale {
    @KsSymbolName("__kk_locale_new_flat")
    public constructor(identifier: String)

    @KsSymbolName("__kk_locale_new_language_country_flat")
    public constructor(language: String, country: String)

    @KsSymbolName("__kk_locale_toString_flat")
    private external fun __localeToString(): String

    public fun getLanguage(): String = localeGetLanguage(this)

    public fun getCountry(): String = localeGetCountry(this)

    public fun getVariant(): String = localeGetVariant(this)

    public fun getDisplayName(): String = localeGetDisplayName(this, getDefault())

    public fun getDisplayName(displayLocale: Locale): String = localeGetDisplayName(this, displayLocale)

    public fun getDisplayLanguage(): String = localeGetDisplayLanguage(this, getDefault())

    public fun getDisplayLanguage(displayLocale: Locale): String = localeGetDisplayLanguage(this, displayLocale)

    public fun getDisplayCountry(): String = localeGetDisplayCountry(this, getDefault())

    public fun getDisplayCountry(displayLocale: Locale): String = localeGetDisplayCountry(this, displayLocale)

    public fun toLanguageTag(): String = localeToLanguageTag(this)

    public val language: String
        get() = getLanguage()

    public val country: String
        get() = getCountry()

    public val variant: String
        get() = getVariant()

    public override fun toString(): String = __localeToString()

    public companion object {
        public val ROOT: Locale
            get() = Locale("")
        public val CANADA: Locale
            get() = Locale("en", "CA")
        public val CANADA_FRENCH: Locale
            get() = Locale("fr", "CA")
        public val CHINA: Locale
            get() = Locale("zh", "CN")
        public val CHINESE: Locale
            get() = Locale("zh")
        public val ENGLISH: Locale
            get() = Locale("en")
        public val FRANCE: Locale
            get() = Locale("fr", "FR")
        public val FRENCH: Locale
            get() = Locale("fr")
        public val GERMANY: Locale
            get() = Locale("de", "DE")
        public val GERMAN: Locale
            get() = Locale("de")
        public val ITALY: Locale
            get() = Locale("it", "IT")
        public val ITALIAN: Locale
            get() = Locale("it")
        public val JAPAN: Locale
            get() = Locale("ja", "JP")
        public val JAPANESE: Locale
            get() = Locale("ja")
        public val KOREA: Locale
            get() = Locale("ko", "KR")
        public val KOREAN: Locale
            get() = Locale("ko")
        public val PRC: Locale
            get() = Locale("zh", "CN")
        public val SIMPLIFIED_CHINESE: Locale
            get() = Locale("zh", "CN")
        public val TAIWAN: Locale
            get() = Locale("zh", "TW")
        public val TRADITIONAL_CHINESE: Locale
            get() = Locale("zh", "TW")
        public val UK: Locale
            get() = Locale("en", "GB")
        public val US: Locale
            get() = Locale("en", "US")

        public fun getDefault(): Locale = localeGetDefault()

        public fun setDefault(locale: Locale) {
            localeSetDefault(locale)
        }

        public fun forLanguageTag(languageTag: String): Locale = localeForLanguageTag(languageTag)
    }
}

@KsSymbolName("__kk_locale_get_default")
private external fun localeGetDefault(): Locale

@KsSymbolName("__kk_locale_set_default")
private external fun localeSetDefault(locale: Locale)

@KsSymbolName("__kk_locale_for_language_tag")
private external fun localeForLanguageTag(languageTag: String): Locale

@KsSymbolName("__kk_locale_get_language")
private external fun localeGetLanguage(locale: Locale): String

@KsSymbolName("__kk_locale_get_country")
private external fun localeGetCountry(locale: Locale): String

@KsSymbolName("__kk_locale_get_variant")
private external fun localeGetVariant(locale: Locale): String

@KsSymbolName("__kk_locale_get_display_name")
private external fun localeGetDisplayName(locale: Locale, displayLocale: Locale): String

@KsSymbolName("__kk_locale_get_display_language")
private external fun localeGetDisplayLanguage(locale: Locale, displayLocale: Locale): String

@KsSymbolName("__kk_locale_get_display_country")
private external fun localeGetDisplayCountry(locale: Locale, displayLocale: Locale): String

@KsSymbolName("__kk_locale_to_language_tag")
private external fun localeToLanguageTag(locale: Locale): String
