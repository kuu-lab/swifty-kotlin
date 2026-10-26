package java.util

/** A Gregorian calendar backed by the platform calendar implementation. */
public class GregorianCalendar : Calendar {
    public constructor() : super(TimeZone.getDefault())

    public constructor(timeZone: TimeZone) : super(timeZone)
}
