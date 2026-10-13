package java.util.Arrays

/**
 * Native implementation of Java's `java.util.Arrays.sort(int[])` entry point.
 * Keep this package facade limited to APIs with an implemented native route.
 */
public fun sort(array: IntArray?) {
    val nonNullArray = array ?: throw NullPointerException()
    nonNullArray.sort()
}
