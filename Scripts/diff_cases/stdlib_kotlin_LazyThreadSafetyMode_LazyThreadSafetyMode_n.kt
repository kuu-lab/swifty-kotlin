fun main() {
    val entries = LazyThreadSafetyMode.entries
    val values = LazyThreadSafetyMode.values()
    println(entries[0])
    println(LazyThreadSafetyMode.valueOf("PUBLICATION"))
    println(values[2])
}
