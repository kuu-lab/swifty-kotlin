package java.util

import kotlin.system.System

/**
 * Minimal `java.util.Date`: an instant held as epoch milliseconds.
 */
public class Date(
    internal var epochMilliseconds: Long,
) {
    public constructor() : this(System.currentTimeMillis())

    public fun getTime(): Long = epochMilliseconds

    public fun setTime(value: Long) {
        epochMilliseconds = value
    }

    public var time: Long
        get() = getTime()
        set(value) = setTime(value)
}
