fun main() {
    val m = mutableMapOf("a" to 1, "b" to 2)
    val entry = m.entries.first()
    entry.setValue(99)
    println(m)
    println(m.values)
    println(m.entries)
    println(entry.value)
}
