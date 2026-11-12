fun main() {
    val source = arrayOf<String?>("a", null)
    val iterable = source.asIterable()
    println(iterable.joinToString(","))
    source[0] = "changed"
    println(iterable.joinToString(","))
    println(emptyArray<String>().asIterable().joinToString(","))
    println(emptyArray<String>().asIterable() is List<*>)
}
