class IndexedLookupBuilder {
    var total = 0
    fun add(value: Int) { total += value }
    fun build(): Int = total
}

fun main() {
    val result = IndexedLookupBuilder().apply {
        for (value in 0..4) {
            if (value % 2 == 0) {
                add(value)
            } else {
                add(1)
            }
        }
    }.build()
    println(result)
}
