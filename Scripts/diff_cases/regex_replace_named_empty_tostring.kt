fun main() {
    val r = Regex("(\\d+)-(\\d+)")
    println(r.replace("1-2 3-4") { it.groupValues[1] + "+" + it.groupValues[2] })
    println(r.replace("1-2 3-4") { "X" })
    println(Regex("\\w+").replace("hello world") { it.value.uppercase() })
    println(Regex("a").toString())
    val n = Regex("(?<year>\\d{4})-(?<month>\\d{2})")
    println(n.replace("2024-05", "$2/$1"))
    println(n.replace("2024-05", "\${month}/\${year}"))
    println(Regex("").findAll("ab").count())
    println(Regex("").replace("ab", "-"))
}
