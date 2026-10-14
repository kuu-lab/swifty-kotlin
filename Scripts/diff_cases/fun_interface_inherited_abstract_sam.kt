// KUU-2165: a `fun interface` that re-declares nothing but inherits exactly one
// abstract function is a valid SAM type, for both lambda conversion and SAM
// constructors; generic arguments flow through the supertype.
interface Base<T> {
    fun run(x: T): String
}

fun interface Derived : Base<Int>

fun interface Redeclared : Base<String> {
    override fun run(x: String): String
}

fun apply(d: Derived): String = d.run(41)

fun main() {
    val d = Derived { it.toString() + "!" }
    println(d.run(3))
    println(apply { (it + 1).toString() })
    val r = Redeclared { it + "?" }
    println(r.run("a"))
}
