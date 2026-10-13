class Solver {
    private infix fun String.diff(other: String): Int = indices.count { this[it] != other[it] }
    fun run(): Int = "abc" diff "axc"
}

private infix fun String.topLevelDiff(other: String): Int = indices.count { this[it] != other[it] }

fun main() {
    println(Solver().run())
    println("abc" topLevelDiff "axc")
}
