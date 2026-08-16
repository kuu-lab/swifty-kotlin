package kotlin

public interface Lazy<out T> {
    public val value: T
    public fun isInitialized(): Boolean
}
