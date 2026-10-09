// KUU-1231: inferred function references expose KCallable metadata and call.
fun topFn(a: Int) = a + 1

fun main() {
    val f = ::topFn
    println(f.name)
    println(f.call(3))
    println(f(3))
    println(f.invoke(3))
}
