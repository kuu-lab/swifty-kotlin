fun main() {
    val source = arrayOf<String?>("ready", null)
    val view = source.asList()
    println(view)
    source[0] = "changed"
    println(view)
    println(emptyArray<String>().asList())
    println(arrayOf(arrayOf("nested")).asList()[0][0])
}
