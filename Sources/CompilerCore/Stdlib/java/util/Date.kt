package java.util

/**
 * Minimal public type shell for Java's Date.
 *
 * The epoch-millisecond value is kept internal until the rest of the Date API
 * is implemented. This is enough to expose Date in signatures such as
 * SimpleDateFormat.parse.
 */
public class Date internal constructor(
    internal val epochMilliseconds: Long,
)
