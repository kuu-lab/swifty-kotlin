import kotlin.reflect.KFunction2

class Box<T>(val value: T)

fun <E> mk(value: E): Box<E> = Box(value)
fun <E> combine(a: E, b: E): E = a

fun <T> makeBox(): (T) -> Box<T> = ::mk
fun <T> makePair(): KFunction2<T, T, T> = ::combine

fun main() {
    val box = makeBox<String>()("hi")
    println(box.value)
    println(makePair<Int>()(3, 4))
}
