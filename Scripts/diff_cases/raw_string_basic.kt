fun constantIndent() = """
    Hello,
    World
""".trimIndent()

fun constantMargin() = """
    |Hello,
    |World
""".trimMargin()

fun constantCustomMargin() = """
    >Hello,
    >World
""".trimMargin(">")

fun main() {
    val s = """hello world"""
    println(s)
    val multi = """
        line1
        line2
    """.trimIndent()
    println(multi)
    println(constantIndent() === constantIndent())
    println(constantMargin() === constantMargin())
    println(constantCustomMargin() === constantCustomMargin())
}
