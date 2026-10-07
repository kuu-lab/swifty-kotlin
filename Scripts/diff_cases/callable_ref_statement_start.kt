// Regression: a statement starting with `::` (callable reference) must not be
// glued onto the previous statement. Kotlin only continues `.`/`?.` across a
// newline, never `::`, so `x\n::prop` parses as `x; ::prop`, not `x::prop`.
var topVar = 9
val topProp = 5
val items = listOf(1, 2, 3)
class Holder { val prop = 41 }

fun main() {
    println("start")
    ::topVar.set(11)
    println(::topVar.get())
    ::topProp.get()
    ::topVar
    run {
        ::topVar.set(21)
        println(::topVar.get())
    }
    val h = Holder()
    println(h::prop.get())
    val chained = items
        .map { it * 2 }
    println(chained)
    println(topVar)
}
