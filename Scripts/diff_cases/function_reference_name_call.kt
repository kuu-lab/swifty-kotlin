// KUU-1231 / KUU-1723: callable references expose metadata and explicit invoke.
fun topFn(a: Int) = a + 1
fun add(a: Int, b: Int) = a + b

fun main() {
    val f = ::topFn
    println(f.name)
    println(f.call(3))
    println(f(3))
    println(f.invoke(3))
    val r = ::add
    println(r(3, 4))
    println(r.invoke(3, 4))
}
