package platform.Foundation

// NSDateFormatterStyle / NSNumberFormatterBehavior are NS_ENUM(NSUInteger)
// in NSDateFormatter.h / NSNumberFormatter.h; Kotlin/Native exposes them as
// typealiases over NSUInteger with top-level constants.
public typealias NSDateFormatterStyle = ULong

public const val NSDateFormatterNoStyle: NSDateFormatterStyle = 0uL
public const val NSDateFormatterShortStyle: NSDateFormatterStyle = 1uL
public const val NSDateFormatterMediumStyle: NSDateFormatterStyle = 2uL
public const val NSDateFormatterLongStyle: NSDateFormatterStyle = 3uL
public const val NSDateFormatterFullStyle: NSDateFormatterStyle = 4uL

public typealias NSNumberFormatterBehavior = ULong

public const val NSNumberFormatterBehaviorDefault: NSNumberFormatterBehavior = 0uL
public const val NSNumberFormatterBehavior10_0: NSNumberFormatterBehavior = 1000uL
public const val NSNumberFormatterBehavior10_4: NSNumberFormatterBehavior = 1040uL

public open class NSDateFormatter internal constructor(handle: Long) : NSObject(handle) {
    public constructor() : this(__foundation_date_formatter_create())

    public var dateFormat: String?
        get() = __foundation_date_formatter_date_format(__handle)
        set(value) { __foundation_date_formatter_set_date_format(__handle, value) }

    public var dateStyle: NSDateFormatterStyle
        get() = __foundation_date_formatter_style(__handle, 0)
        set(value) { __foundation_date_formatter_set_style(__handle, 0, value) }

    public var timeStyle: NSDateFormatterStyle
        get() = __foundation_date_formatter_style(__handle, 1)
        set(value) { __foundation_date_formatter_set_style(__handle, 1, value) }

    public var locale: NSLocale?
        get() = (__foundation_date_formatter_object(__handle, 0) as? Long)?.let { NSLocale(it) }
        set(value) { __foundation_date_formatter_set_object(__handle, 0, value?.__handle ?: -1L) }

    public var timeZone: NSTimeZone?
        get() = (__foundation_date_formatter_object(__handle, 1) as? Long)?.let { NSTimeZone(it) }
        set(value) { __foundation_date_formatter_set_object(__handle, 1, value?.__handle ?: -1L) }

    public var isLenient: Boolean
        get() = __foundation_date_formatter_bool(__handle, 0)
        set(value) { __foundation_date_formatter_set_bool(__handle, 0, value) }

    public var formatterBehavior: NSNumberFormatterBehavior
        get() = __foundation_date_formatter_style(__handle, 2)
        set(value) { __foundation_date_formatter_set_style(__handle, 2, value) }

    public fun stringFromDate(date: NSDate): String =
        __foundation_date_formatter_string_from_date(__handle, date.__handle)

    public fun dateFromString(string: String): NSDate? =
        (__foundation_date_formatter_date_from_string(__handle, string) as? Long)?.let { NSDate(it) }

    public companion object {}
}

public fun NSDateFormatter.Companion.localizedStringFromDate(
    date: NSDate,
    dateStyle: NSDateFormatterStyle,
    timeStyle: NSDateFormatterStyle
): String = __foundation_date_formatter_localized_string(date.__handle, dateStyle, timeStyle)

public fun NSDateFormatter.Companion.dateFormatFromTemplate(
    template: String,
    options: ULong,
    locale: NSLocale?
): String? = __foundation_date_formatter_format_from_template(template, options, locale?.__handle ?: -1L)
