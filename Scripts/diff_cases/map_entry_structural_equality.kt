// KUU-1844: Map.Entry equality compares both key and value structurally.
fun main() {
    val m = mutableMapOf("a" to 1)
    println(m.entries.first() == m.entries.first())

    val same = mutableMapOf("a" to 1)
    val differentKey = mutableMapOf("b" to 1)
    val differentValue = mutableMapOf("a" to 2)
    val entry = m.entries.first()
    println(entry == same.entries.first())
    println(entry == differentKey.entries.first())
    println(entry == differentValue.entries.first())

    val readOnlyEntry = mapOf("a" to 1).entries.first()
    println(entry == readOnlyEntry)
    println(readOnlyEntry == entry)
}
