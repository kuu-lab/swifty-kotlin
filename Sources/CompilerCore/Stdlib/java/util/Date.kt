package java.util

import kotlin.system.System

public class Date(
    internal var epochMilliseconds: Long,
) : Comparable<Date> {
    public constructor() : this(System.currentTimeMillis())

    public fun getTime(): Long = epochMilliseconds

    public fun setTime(value: Long) {
        epochMilliseconds = value
    }

    public var time: Long
        get() = getTime()
        set(value) = setTime(value)

    public fun after(other: Date): Boolean = epochMilliseconds > other.epochMilliseconds

    public fun before(other: Date): Boolean = epochMilliseconds < other.epochMilliseconds

    public override fun compareTo(other: Date): Int =
        epochMilliseconds.compareTo(other.epochMilliseconds)

    public override fun equals(other: Any?): Boolean =
        other is Date && epochMilliseconds == other.epochMilliseconds

    public override fun hashCode(): Int =
        (epochMilliseconds xor (epochMilliseconds ushr 32)).toInt()
}
