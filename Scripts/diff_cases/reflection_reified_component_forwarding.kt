inline fun <reified T> forwardedEmpty(): Array<T> = arrayOf<T>()

inline fun <reified T> capturedEmpty(): Array<T> {
    val supplier = { forwardedEmpty<T>() }
    return supplier()
}

inline fun <reified T> T.receiverEmpty(): Array<T> = arrayOf<T>()
inline fun <reified U> typedEmpty(value: U & Any): Array<*> = value.receiverEmpty()
fun <U> erasedEmpty(value: U & Any): Array<*> = value.receiverEmpty()

fun forwardedStrings(vararg values: String): Int = values.size
fun forwardedNested(vararg values: Array<String>): Int = values.size

fun forwardingStatus(action: () -> Any?): String = try {
    action()
    "OK"
} catch (_: IllegalArgumentException) {
    "IAE"
}

fun main() {
    val strings = ::forwardedStrings
    println("captured:" + strings.callBy(mapOf(strings.parameters[0] to capturedEmpty<String>())))
    println("intersection:" + strings.callBy(mapOf(strings.parameters[0] to typedEmpty<String>("x"))))
    println("erased:" + forwardingStatus {
        strings.callBy(mapOf(strings.parameters[0] to erasedEmpty<String>("x")))
    })
    val nested = ::forwardedNested
    println("captured-nested:" + nested.callBy(mapOf(nested.parameters[0] to capturedEmpty<Array<String>>())))
}
