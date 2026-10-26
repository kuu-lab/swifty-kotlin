abstract class Factory {
    abstract fun dropAll(): Unit companion object { const val ERROR_SEPARATOR = "separator" }
}

class ConcreteFactory : Factory() {
    override fun dropAll() {}
}

fun companion(): Int = 4
fun call(): Int =
    companion()
infix fun Int.companion(other: Any): Int = this

fun main() {
    println(Factory.ERROR_SEPARATOR)
    println(call())
    println(3 companion object {})
    ConcreteFactory().dropAll()
}
