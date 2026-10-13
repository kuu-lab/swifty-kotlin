enum class Event { START, TEXT, CDATA, END }

private fun event(cdata: Boolean): Event {
    val result: Event
    if (cdata) result = Event.CDATA else result = Event.TEXT
    return result
}

private fun integerValue(flag: Boolean): Int {
    val result: Int
    if (flag) result = 42 else result = 17
    return result
}

private fun referenceValue(flag: Boolean): String {
    val result: String
    if (flag) result = "alpha" else result = "beta"
    return result
}

fun main() {
    println(event(true))
    println(event(false))
    println(integerValue(true))
    println(integerValue(false))
    println(referenceValue(true))
    println(referenceValue(false))
}
