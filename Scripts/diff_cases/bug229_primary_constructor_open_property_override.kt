open class Base(open val p: String)

class Derived(p: String) : Base(p) {
    override val p: String = p + "!"
}

fun readBase(value: Base): String = value.p

fun main() {
    println(readBase(Derived("base")))
}
