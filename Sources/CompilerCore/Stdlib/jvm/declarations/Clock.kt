package kotlin.time

public interface Clock {
    public fun now(): Instant

    public object System : Clock {
        override fun now(): Instant = null!!
    }

    public companion object
}
