// KUU-3125: Enum.compareTo returns the ordinal difference, not only its sign.
enum class Col { RED, GREEN, BLUE, YELLOW }

private fun <T : Enum<T>> compareGeneric(lhs: T, rhs: T): Int = lhs.compareTo(rhs)

fun main() {
    println(Col.RED.compareTo(Col.BLUE))
    println(Col.BLUE.compareTo(Col.RED))
    println(Col.RED.compareTo(Col.GREEN))
    println(Col.YELLOW.compareTo(Col.RED))
    println(Col.BLUE.compareTo(Col.BLUE))
    println(compareGeneric(Col.RED, Col.BLUE))
}
