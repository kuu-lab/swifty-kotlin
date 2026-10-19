package java.util

/**
 * The epoch-millisecond value is kept internal until the rest of the Date API
 * is implemented. This is enough to expose Date in signatures such as
 * SimpleDateFormat.parse.
 */
public class Date internal constructor(
    internal val epochMilliseconds: Long,
)
