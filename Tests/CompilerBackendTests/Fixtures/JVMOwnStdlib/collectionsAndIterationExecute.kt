fun main() {
    val values = mutableListOf(2, 3, 4)
    values.add(5)
    values[0] = 10
    println(values.size)
    println(values.removeAt(1))
    var sum = 0
    for (value in values) { if (value == 4) continue; sum += value }
    println(sum)
    val view: List<Int> = values
    println(view[1])
    val names = setOf("a", "b", "a")
    println(names.size)
    for (name in names) { println(name) }
    val counts = mutableMapOf<String, Int>()
    counts["answer"] = 42
    println(counts["answer"]!!)
    println(counts["absent"])
    println(counts.containsKey("answer"))
    for (key in counts.keys) { println(key) }
    val initial = mapOf("a" to 1, "b" to 2)
    println(initial["b"])
    println(emptyList<String>().isEmpty())
}
