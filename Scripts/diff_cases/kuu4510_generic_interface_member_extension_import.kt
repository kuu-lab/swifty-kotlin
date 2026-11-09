import C.fi
import C.pick

interface I<T> {
    fun <E> E.fi(): E = this
    fun pick(value: T): T = value
}
object C : I<String>

fun main() {
    println(9.fi())
    println("OK".fi())
    println(pick("item"))
}
