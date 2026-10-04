@file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
import kotlin.coroutines.intrinsics.CoroutineSingletons

fun main() {
    println(CoroutineSingletons.values().size)
    println(CoroutineSingletons.entries.size)
    for (value in CoroutineSingletons.values()) println(value.name)
    val values = CoroutineSingletons.values()
    println(values[0] == CoroutineSingletons.COROUTINE_SUSPENDED)
    println(values[1] == CoroutineSingletons.UNDECIDED)
    println(values[2] == CoroutineSingletons.RESUMED)
    println(CoroutineSingletons.valueOf("RESUMED") == CoroutineSingletons.RESUMED)
    try {
        CoroutineSingletons.valueOf("missing")
    } catch (exception: IllegalArgumentException) {
        println("missing")
    }
}
