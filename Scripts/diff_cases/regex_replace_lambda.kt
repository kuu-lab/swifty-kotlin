fun main() {
    val regex = Regex("(\\d+)-(\\d+)")
    println(regex.replace("1-2 3-4") { it.groupValues[1] + "+" + it.groupValues[2] })
    println(regex.replace("1-2 3-4") { "X" })
    println(Regex("\\w+").replace("hello world") { it.value.uppercase() })
}
