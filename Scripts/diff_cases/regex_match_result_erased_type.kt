fun <T> identity(value: T): T = value

fun main() {
    val regex = Regex("a")
    val match = regex.find("aba")!!
    val erased: Any = match
    println(erased is MatchResult)
    println(erased is Regex)
    println((erased as MatchResult).value)
    println(identity(match).next()!!.value)
    println(sequenceOf(match).first().value)
    println(regex.findAll("aba").map { it.value }.toList())
    println(regex.matchEntire("a")!!.value)
}
