package kotlin.time

public interface Clock {
    public fun now(): Instant

    public object System : Clock {
        override fun now(): Instant = Instant.now()
    }

    public companion object
}
