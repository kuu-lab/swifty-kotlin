// KUU-1267: escaped null is a name, while bare null remains a literal.
fun read(`null`: Int): Int = `null` + 1

class NullHolder(val `null`: Int)

fun main() {
    val `null` = 14
    println(`null`)
    println(`null` + 1)
    println(read(`null`))
    println(NullHolder(16).`null`)
    println(null)
    println(`null` == null)
    val value: Int? = 14
    println(when (value) {
        `null` -> "variable"
        null -> "literal"
        else -> "other"
    })
    val missing: Int? = null
    println(when (missing) {
        `null` -> "variable"
        null -> "literal"
        else -> "other"
    })
    val producer = { `null` }
    println(producer())
}
