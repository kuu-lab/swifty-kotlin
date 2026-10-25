// KUU-3212: a `private` member of an enclosing class is not inherited, so a
// bare reference inside an anonymous object that subclasses it must resolve
// to the enclosing instance — never the object's own same-named slot.
open class X(private val n: String) {
    private fun tag(): String = n
    fun prop(): String = object : X("inner") { fun print() = n }.print()
    fun call(): String = object : X("inner") { fun print() = tag() }.print()
}
fun main() {
    val x = X("OK")
    println(x.prop())
    println(x.call())
}
