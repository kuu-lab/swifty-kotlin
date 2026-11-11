fun main() {
    val deque = ArrayDeque<String?>(2)
    deque.addLast(null)
    deque.addLast("a")
    check(deque.removeFirst() == null)
    deque.addLast("b")
    deque.addFirst("head")
    deque.add(2, "middle")
    check(deque.toList() == listOf("head", "a", "middle", "b"))
    check(deque.removeAt(2) == "middle")
    deque.addAll(deque)
    check(deque.toList() == listOf("head", "a", "b", "head", "a", "b"))
    val cursor = deque.iterator()
    check(cursor.next() == "head")
    deque.removeLast()
    try {
        cursor.next()
        error("iterator accepted structural modification")
    } catch (_: ConcurrentModificationException) {}

    val map = object : AbstractMap<String, String>() {
        override val entries: Set<Map.Entry<String, String>> = mapOf("key" to "value").entries
    }
    check(map.size == 1)
    check(map["key"] == "value")
    check(map.keys == setOf("key"))
    check(map.values.single() == "value")
    val set = object : AbstractSet<Int>() {
        override val size: Int get() = 1
        override fun iterator(): Iterator<Int> = listOf(42).iterator()
    }
    check(set.size == 1 && set.contains(42))
    val mutableMap = object : AbstractMutableMap<String, String>() {
        private val backing = mutableMapOf<String, String>()
        override val entries get() = backing.entries
        override fun put(key: String, value: String): String? = backing.put(key, value)
    }
    mutableMap["new"] = "entry"
    check(mutableMap.size == 1 && mutableMap["new"] == "entry")

    val floats = floatArrayOf(3f, 2f, 1f)
    check(floats.copyInto(FloatArray(2), startIndex = 1).contentEquals(floatArrayOf(2f, 1f)))
    val words = arrayOf("keep", "z", "a", "last")
    words.sortWith(Comparator { first, second -> first.compareTo(second) }, 1, 3)
    check(words.contentEquals(arrayOf("keep", "a", "z", "last")))
    check(words.copyOfRange(1, 3).contentEquals(arrayOf("a", "z")))
    try {
        words.copyOfRange(1, 5)
        error("copyOfRange accepted an invalid end index")
    } catch (_: IndexOutOfBoundsException) {}
    check(7.coerceIn(0, 5) == 5)
    check((-1f).coerceIn(0f, 5f) == 0f)
    check(Float.NaN.coerceIn(0f, 1f).isNaN())
    val list = mutableListOf(3, 1, 2)
    list.sortWith(Comparator { first, second -> first.compareTo(second) })
    check(list.removeFirst() == 1 && list.removeLast() == 3)
    println("ok")
}
