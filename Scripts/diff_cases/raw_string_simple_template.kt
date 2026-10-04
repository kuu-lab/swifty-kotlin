fun main() {
    val v = 1
    val s = "x"

    println("""raw $v ${s}""")
    println("""$v""")
    println("""a$v""")
    println("""$s$v""")
    println("""line1
$v line2""")
    println("""$s$v""".length)
}
