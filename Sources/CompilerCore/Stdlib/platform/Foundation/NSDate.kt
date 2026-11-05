package platform.Foundation

// NSTimeInterval is Double on 64-bit Darwin (NSDate.h).
public typealias NSTimeInterval = Double

// NSComparisonResult is NS_ENUM(NSInteger) in NSObjCRuntime.h.
public typealias NSComparisonResult = platform.darwin.NSInteger

public const val NSComparisonResultOrderedAscending: NSComparisonResult = -1L
public const val NSComparisonResultOrderedSame: NSComparisonResult = 0L
public const val NSComparisonResultOrderedDescending: NSComparisonResult = 1L

/**
 * Typed facade over a real Foundation NSDate. Mirrors the Kotlin/Native
 * platform.Foundation surface: `timeIntervalSince1970`/`timeIntervalSinceNow`/
 * `timeIntervalSinceReferenceDate` are member properties (they are readonly
 * ObjC properties), while the zero-argument call forms are top-level
 * extensions, matching KN's `platform.Foundation.timeIntervalSince1970`.
 */
public open class NSDate internal constructor(handle: Long) : NSObject(handle) {
    /** -[NSDate init]: the current date and time. */
    public constructor() : this(__foundation_date_now())
    public constructor(timeIntervalSinceReferenceDate: NSTimeInterval) :
        this(__foundation_date_create_reference(timeIntervalSinceReferenceDate))
    public constructor(timeInterval: NSTimeInterval, sinceDate: NSDate) :
        this(__foundation_date_create_since(timeInterval, sinceDate.__handle))

    public val timeIntervalSince1970: NSTimeInterval
        get() = __foundation_date_interval(__handle, 0)
    public val timeIntervalSinceNow: NSTimeInterval
        get() = __foundation_date_interval(__handle, 1)
    public val timeIntervalSinceReferenceDate: NSTimeInterval
        get() = __foundation_date_interval(__handle, 2)

    public fun dateByAddingTimeInterval(secondsToBeAdded: NSTimeInterval): NSDate =
        NSDate(__foundation_date_add(__handle, secondsToBeAdded))

    public fun earlierDate(otherDate: NSDate): NSDate =
        NSDate(__foundation_date_extreme(__handle, otherDate.__handle, 0))

    public fun laterDate(otherDate: NSDate): NSDate =
        NSDate(__foundation_date_extreme(__handle, otherDate.__handle, 1))

    public fun compare(otherDate: NSDate): NSComparisonResult =
        __foundation_date_compare(__handle, otherDate.__handle)

    public fun isEqualToDate(otherDate: NSDate?): Boolean =
        __foundation_date_is_equal(__handle, otherDate?.__handle ?: -1L)

    public fun timeIntervalSinceDate(otherDate: NSDate): NSTimeInterval =
        __foundation_date_interval_since(__handle, otherDate.__handle)

    public companion object {}
}

// Kotlin/Native exposes the ObjC class methods as companion members.
public fun NSDate.Companion.date(): NSDate = NSDate()

public val NSDate.Companion.now: NSDate
    get() = NSDate()

public val NSDate.Companion.distantPast: NSDate
    get() = NSDate(__foundation_date_distant(0))

public val NSDate.Companion.distantFuture: NSDate
    get() = NSDate(__foundation_date_distant(1))

public val NSDate.Companion.timeIntervalSinceReferenceDate: NSTimeInterval
    get() = NSDate().timeIntervalSinceReferenceDate

public fun NSDate.Companion.dateWithTimeIntervalSinceNow(seconds: NSTimeInterval): NSDate =
    NSDate(__foundation_date_factory_since_now(seconds))

public fun NSDate.Companion.dateWithTimeIntervalSinceReferenceDate(seconds: NSTimeInterval): NSDate =
    NSDate(__foundation_date_create_reference(seconds))

public fun NSDate.Companion.dateWithTimeIntervalSince1970(seconds: NSTimeInterval): NSDate =
    NSDate(__foundation_date_factory_since1970(seconds))

public fun NSDate.Companion.dateWithTimeInterval(seconds: NSTimeInterval, sinceDate: NSDate): NSDate =
    NSDate(__foundation_date_factory_since(seconds, sinceDate.__handle))

// Zero-argument call forms of the readonly ObjC time-interval properties,
// provided by Kotlin/Native as top-level extensions in platform.Foundation.
public fun NSDate.timeIntervalSince1970(): NSTimeInterval = timeIntervalSince1970
public fun NSDate.timeIntervalSinceNow(): NSTimeInterval = timeIntervalSinceNow
public fun NSDate.timeIntervalSinceReferenceDate(): NSTimeInterval = timeIntervalSinceReferenceDate
