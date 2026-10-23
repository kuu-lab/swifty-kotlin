package java.util

public interface Enumeration<out E> {
    public fun hasMoreElements(): Boolean
    public fun nextElement(): E
}
