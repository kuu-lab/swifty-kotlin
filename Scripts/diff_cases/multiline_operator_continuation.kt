val total: Int = 1 +
    (2 + 3)

val flag: Boolean = false ||
    (
        true && total > 0
    )

fun sum(): Int = total +
    4

fun label(): String = "total=" +
    total.toString()

class Version(val major: Int, val minor: Int) {
    fun isAtLeast(major: Int, minor: Int): Boolean =
        this.major > major ||
            (this.major == major && this.minor >= minor)
}

fun main() {
    println(total)
    println(flag)
    println(sum())
    println(label())

    val version = Version(2, 1)
    println(version.isAtLeast(2, 1))
    println(version.isAtLeast(2, 2))
    println(version.isAtLeast(1, 9))

    val chained = 1 +
        2 *
        3 -
        1
    println(chained)

    val nullable: Int? = null
    val fallback = nullable ?:
        7
    println(fallback)
}
