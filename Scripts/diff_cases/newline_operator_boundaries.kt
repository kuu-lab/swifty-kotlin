fun answer(): Int
    = 42

val top: Int
    = 7

fun main() {
    val n = 1
    + 2
    println(n)
    val m = 1
    - 2
    println(m)
    var x = 4
    x
    + 3
    x
    - 3
    println(x)
    val nested = {
        val y = 1
        + 2
        y
    }
    println(nested())
    fun local(): Int {
        val y = 1
        - 2
        return y
    }
    println(local())
    fun expression(): Int
        = 8
    println(expression())
    println(answer())
    println(top)
    val declared: Int
        = 9
    println(declared)
    val grouped = (1
        + 2)
    println(grouped)
    val trailing = 1 +
        2
    println(trailing)
    val text = " hi "
        .trim()
    println(text)
    val nullable: String? = " hi "
    println(nullable
        ?.trim()
        ?: "none")
    val yes = true
        && true
        || false
    println(yes)
    val boxed: Any = 5
    val cast = boxed
        as Int
    println(cast)
    val safeCast = boxed
        as? Int
    println(safeCast)
    val result = when (n) {
        1
            -> 10
        else
            -> 20
    }
    println(result)
    val branch = if (true) {
        val y = 1
        + 2
        y
    } else { 0 }
    println(branch)
}
