class Values(val value: String)

operator fun Values.iterator(): Iterator<String> = object : Iterator<String> {
    var count = 0
    override fun hasNext(): Boolean = count < 2
    override fun next(): String { count++; return value }
}

fun main() {
    for (value in Values("Z")) println(value)
}
