fun main() {
    val values = arrayOf("left", "right")
    println("%s %s".format(*values))

    val mixed = arrayOf("age", "7")
    println("%s:%s".format(*mixed))
}
