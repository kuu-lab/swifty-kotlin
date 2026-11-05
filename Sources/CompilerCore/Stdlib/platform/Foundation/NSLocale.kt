package platform.Foundation

// -[NSLocale init] is NS_UNAVAILABLE; initWithLocaleIdentifier: is the only
// public initializer.
public open class NSLocale internal constructor(handle: Long) : NSObject(handle) {
    public constructor(localeIdentifier: String) : this(__foundation_locale_create_identifier(localeIdentifier))

    public val localeIdentifier: String
        get() = __foundation_locale_identifier(__handle)

    public val languageCode: String?
        get() = __foundation_locale_language_code(__handle)

    public val countryCode: String?
        get() = __foundation_locale_country_code(__handle)

    public companion object {}
}

public val NSLocale.Companion.currentLocale: NSLocale
    get() = NSLocale(__foundation_locale_current())

public val NSLocale.Companion.autoupdatingCurrentLocale: NSLocale
    get() = NSLocale(__foundation_locale_autoupdating())

public fun NSLocale.Companion.localeWithLocaleIdentifier(identifier: String): NSLocale =
    NSLocale(__foundation_locale_with_identifier(identifier))
