enum class Direction { NORTH, SOUTH }

fun enumCompanion(): Any = Enum.Companion

fun main() {
    enumCompanion()
    println("ok")
}
