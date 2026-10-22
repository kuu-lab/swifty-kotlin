package java.util

import kotlin.system.System

/**
 * Minimal `java.util.Date`: an instant held as epoch milliseconds.
 */
public class Date(
    internal val epochMilliseconds: Long,
) {
    public constructor() : this(System.currentTimeMillis())

    public fun getTime(): Long = epochMilliseconds
}
