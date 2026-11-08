interface R

fun <A> f(block: suspend context(R) () -> A): A = TODO()

fun main() {
    println("ok")
}
