// KUU-1852: Empty arrays retain allocation components across erased returns
// and reified inline bodies, including bodies imported from a real .kklib.
fun emptyProbeCount(vararg values: String): Int = values.size
fun emptyNestedCount(vararg values: Array<String>): Int = values.size
fun emptyBoxedCount(vararg values: Number): Int = values.size
fun emptyAnyCount(vararg values: Any): Int = values.size
fun emptyPrimitiveCount(vararg values: Int): Int = values.size
fun emptyPrimitiveNestedCount(vararg values: IntArray): Int = values.size

inline fun <reified T> typedEmpty(): Array<T> = emptyArray<T>()
inline fun <reified T> capturedTypedEmpty(): Array<T> {
    val supplier = { emptyArray<T>() }
    return supplier()
}
inline fun <reified T> defaultTypedEmpty(supplier: () -> Array<T> = { emptyArray<T>() }): Array<T> = supplier()
inline fun <reified T> T.receiverTypedEmpty(): Array<T> = emptyArray<T>()
inline fun <reified U> intersectionTypedEmpty(value: U & Any): Array<*> = value.receiverTypedEmpty()
fun <U> erasedTypedEmpty(value: U & Any): Array<*> = value.receiverTypedEmpty()
fun <T> eraseEmpty(values: Array<T>): Array<*> = values
fun widenedEmpty(): Array<out Any> = emptyArray<String>()
fun wrongEmpty(): Array<out Any> = emptyArray<Any>()
fun emptyCallStatus(action: () -> Any?): String = try {
    action()
    "OK"
} catch (_: IllegalArgumentException) {
    "IAE"
}

fun main() {
    val reference = ::emptyProbeCount
    try {
        println("empty:" + reference.callBy(mapOf(reference.parameters[0] to emptyArray<String>())))
    } catch (_: IllegalArgumentException) {
        println("empty:IAE")
    }
    val parameter = reference.parameters[0]
    println("reified:" + reference.callBy(mapOf(parameter to typedEmpty<String>())))
    println("captured:" + reference.callBy(mapOf(parameter to capturedTypedEmpty<String>())))
    println("default:" + reference.callBy(mapOf(parameter to defaultTypedEmpty<String>())))
    println("erased:" + reference.callBy(mapOf(parameter to eraseEmpty(emptyArray<String>()))))
    println("intersection:" + reference.callBy(mapOf(parameter to intersectionTypedEmpty<String>("x"))))
    println("erased-allocation:" + emptyCallStatus { reference.callBy(mapOf(parameter to erasedTypedEmpty<String>("x"))) })
    println("widened:" + reference.callBy(mapOf(parameter to widenedEmpty())))
    println("wrong-any:" + emptyCallStatus { reference.callBy(mapOf(parameter to wrongEmpty())) })
    println("wrong-int:" + emptyCallStatus { reference.callBy(mapOf(parameter to emptyArray<Int>())) })
    println("wrong-reified:" + emptyCallStatus { reference.callBy(mapOf(parameter to typedEmpty<Any>())) })
    println("wrong-erased:" + emptyCallStatus { reference.callBy(mapOf(parameter to eraseEmpty(emptyArray<Any>()))) })
    val nested = ::emptyNestedCount
    val nestedParameter = nested.parameters[0]
    println("nested:" + nested.callBy(mapOf(nestedParameter to emptyArray<Array<String>>())))
    println("nested-captured:" + nested.callBy(mapOf(nestedParameter to capturedTypedEmpty<Array<String>>())))
    println("nested-default:" + nested.callBy(mapOf(nestedParameter to defaultTypedEmpty<Array<String>>())))
    println("nested-wrong:" + emptyCallStatus { nested.callBy(mapOf(nestedParameter to emptyArray<Array<Any>>())) })
    val boxed = ::emptyBoxedCount
    println("boxed:" + boxed.callBy(mapOf(boxed.parameters[0] to emptyArray<Int>())))
    println("boxed-reified:" + boxed.callBy(mapOf(boxed.parameters[0] to typedEmpty<Int>())))
    val primitive = ::emptyPrimitiveCount
    println("primitive-rejects-boxed:" + emptyCallStatus { primitive.callBy(mapOf(primitive.parameters[0] to emptyArray<Int>())) })
    val primitiveNested = ::emptyPrimitiveNestedCount
    println("primitive-nested:" + primitiveNested.callBy(mapOf(primitiveNested.parameters[0] to typedEmpty<IntArray>())))
    println("fresh:" + (emptyArray<String>() !== emptyArray<String>()))
    val stable = emptyArray<String>()
    reference.callBy(mapOf(parameter to stable))
    println("identity:" + (stable === eraseEmpty(stable)))
    val any = ::emptyAnyCount
    println("any:" + any.callBy(mapOf(any.parameters[0] to stable)))
    println("string-after-any:" + reference.callBy(mapOf(parameter to stable)))
}
