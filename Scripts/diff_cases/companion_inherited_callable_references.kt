abstract class Base {
    fun foo(): String = "A"
    abstract fun bar(): String
}

object Singleton : Base() {
    override fun bar(): String = "C"
}

class Some {
    companion object : Base() {
        override fun bar(): String = "B"
    }
}

fun main() {
    println((Singleton::foo)())
    println((Singleton::bar)())
    println((Some::foo)())
    println((Some::bar)())
    println((Some.Companion::foo)())
}
