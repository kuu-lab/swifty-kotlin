// KSP-486: MatchResult / MatchGroup public layer (Kotlin source), covering the
// destructured components, named/indexed group lookup, ranges and next().
fun main() {
    val regex = Regex("(?<user>[a-z]+)@(?<host>[a-z.]+)")
    val match = regex.find("mail: user@example.com !")
    if (match != null) {
        val (user, host) = match.destructured
        println(user)
        println(host)
        println(match.destructured.match.value)

        println(match.value)
        println(match.range.first)
        println(match.range.last)
        println(match.groupValues.size)
        println(match.groupValues[1])

        val groups = match.groups
        println(groups.size)
        println(groups[0]?.value)
        println(groups["user"]?.value)
        println(groups["host"]?.value)
        val userGroup = groups["user"]
        if (userGroup != null) {
            println(userGroup.range.first)
            println(userGroup.range.last)
        }
    }

    val optional = Regex("(a)(b)?(c)")
    val optionalMatch = optional.find("ac")
    if (optionalMatch != null) {
        println(optionalMatch.groups[2]?.value)
        println(optionalMatch.groupValues[2])
    }

    val numbers = Regex("\\d+")
    var current = numbers.find("a1b22c333")
    while (current != null) {
        println(current.value)
        current = current.next()
    }
}
