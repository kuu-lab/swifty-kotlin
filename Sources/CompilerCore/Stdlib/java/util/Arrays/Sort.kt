package java.util.Arrays

/** Keep this package facade limited to APIs with an implemented native route. */
public fun sort(array: IntArray?) {
    val nonNullArray = array ?: throw NullPointerException()
    nonNullArray.sort()
}
