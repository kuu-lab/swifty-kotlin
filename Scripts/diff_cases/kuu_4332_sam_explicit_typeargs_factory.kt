import java.util.function.Function
import java.util.Optional

class Box<T : Any>(val v: T) {
    companion object {
        fun <T : Any> of(v: T): Box<T> = Box(v)
    }
}
fun interface Fn<T, R> { fun apply(x: T): R }

fun main() {
    val a = Function<Int, Optional<Int>> { Optional.of(it + 10) }
    println(a.apply(1).get())

    val b = Fn<Int, Box<Int>> { x -> Box.of(x + 10) }
    println(b.apply(2).v)
}
