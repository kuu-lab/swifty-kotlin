fun fail(): Int = throw IllegalStateException("failure")
val broken: Int get() = throw IllegalArgumentException("getter")
fun main() {
    try { ::fail.call() } catch (e: Throwable) { println(e.javaClass.name) }
    val callback = ::fail
    try { callback() } catch (e: Throwable) { println(e.javaClass.name) }
    try { ::broken.call() } catch (e: Throwable) { println(e.javaClass.name) }
    try { ::broken.get() } catch (e: Throwable) { println(e.javaClass.name) }
}
