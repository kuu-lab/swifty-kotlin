package java.util

import kotlin.internal.KsSymbolName

/** A Gregorian calendar backed by the platform calendar implementation. */
public class GregorianCalendar : Calendar {
    public constructor() : super(TimeZone.getDefault())

    public constructor(timeZone: TimeZone) : super(timeZone)

    public constructor(year: Int, month: Int, day: Int) : this(year, month, day, 0, 0, 0)

    public constructor(year: Int, month: Int, day: Int, hourOfDay: Int, minute: Int) :
        this(year, month, day, hourOfDay, minute, 0)

    public constructor(year: Int, month: Int, day: Int, hourOfDay: Int, minute: Int, second: Int) :
        super(
            calendarCreateFields(
                TimeZone.getDefault().rawHandle,
                year,
                month,
                day,
                hourOfDay,
                minute,
                second
            )
        )
}

// The runtime resolves the field set atomically so intermediate overflow
// normalization (e.g. Feb 30 rolling into March) cannot corrupt other fields.
@KsSymbolName("__kk_calendar_create_fields")
private external fun calendarCreateFields(
    timeZoneRaw: Long,
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    minute: Int,
    second: Int
): Long
