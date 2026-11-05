package platform.Foundation

public open class NSTimeZone internal constructor(handle: Long) : NSObject(handle) {
    // initWithAbbreviation: shares the String signature with initWithName: and
    // is reachable through +timeZoneWithAbbreviation: instead.
    public constructor(name: String) : this(__foundation_timezone_create_name(name))

    /** Non-null in Kotlin/Native: every NSTimeZone vendored by Foundation has a name. */
    public val name: String
        get() = __foundation_timezone_name(__handle)

    public val abbreviation: String?
        get() = __foundation_timezone_abbreviation(__handle)

    public val secondsFromGMT: Long
        get() = __foundation_timezone_seconds_from_gmt(__handle)

    public fun secondsFromGMTForDate(date: NSDate): Long =
        __foundation_timezone_seconds_from_gmt_for_date(__handle, date.__handle)

    public fun abbreviationForDate(date: NSDate): String? =
        __foundation_timezone_abbreviation_for_date(__handle, date.__handle)

    /** isEqualToTimeZone: compares the zone identity, not just the offset. */
    public fun isEqualToTimeZone(otherTimeZone: NSTimeZone): Boolean =
        __foundation_timezone_is_equal(__handle, otherTimeZone.__handle)

    public companion object {}
}

public val NSTimeZone.Companion.localTimeZone: NSTimeZone
    get() = NSTimeZone(__foundation_timezone_local())

public val NSTimeZone.Companion.systemTimeZone: NSTimeZone
    get() = NSTimeZone(__foundation_timezone_system())

public fun NSTimeZone.Companion.timeZoneWithName(name: String): NSTimeZone? =
    (__foundation_timezone_with_name(name) as? Long)?.let { NSTimeZone(it) }

public fun NSTimeZone.Companion.timeZoneWithAbbreviation(abbreviation: String): NSTimeZone? =
    (__foundation_timezone_with_abbreviation(abbreviation) as? Long)?.let { NSTimeZone(it) }

public fun NSTimeZone.Companion.timeZoneForSecondsFromGMT(seconds: Long): NSTimeZone =
    NSTimeZone(__foundation_timezone_for_seconds_from_gmt(seconds))
