fun <T> genericHash(value: T): Int = value.hashCode()

fun main() {
    val unitHash = Unit.hashCode()
    val erased: Any = Unit
    val erasedHash = erased.hashCode()

    println(unitHash != 0)
    println(unitHash == Unit.hashCode())
    println(unitHash == erasedHash)
    println(unitHash == genericHash(Unit))
    println(0.hashCode() == 0)
}
