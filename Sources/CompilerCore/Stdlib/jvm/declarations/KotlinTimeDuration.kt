package kotlin.time

@JvmInline
public value class Duration internal constructor(internal val rawValue: Long) {
    public val inWholeNanoseconds: Long get() = 0L
    public val inWholeMilliseconds: Long get() = 0L
    public val inWholeSeconds: Long get() = 0L
    public fun isNegative(): Boolean = false

    public companion object {
        public val Int.seconds: Duration get() = Duration(0L)
        public val Long.seconds: Duration get() = Duration(0L)
        public val Double.seconds: Duration get() = Duration(0L)
    }
}
