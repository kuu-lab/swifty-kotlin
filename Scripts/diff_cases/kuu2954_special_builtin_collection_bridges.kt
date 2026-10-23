// KUU-2954: collection implementations specialised to Nothing/Any must carry
// JVM-style type-safe barriers on their erased `Object` bridge slots, so
// calls through `List<String>`/`MutableMap<Any?, Any?>` receivers answer the
// member's erased default instead of reaching a narrowed parameter.

private object EmptyListOfNothing : List<Nothing> {
    override fun contains(element: Nothing): Boolean = false
    override fun containsAll(elements: Collection<Nothing>): Boolean = elements.isEmpty()
    override fun indexOf(element: Nothing): Int = -2
    override fun lastIndexOf(element: Nothing): Int = -2

    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true

    override fun iterator(): Iterator<Nothing> = throw UnsupportedOperationException()
    override fun get(index: Int): Nothing = throw UnsupportedOperationException()
    override fun listIterator(): ListIterator<Nothing> = throw UnsupportedOperationException()
    override fun listIterator(index: Int): ListIterator<Nothing> = throw UnsupportedOperationException()
    override fun subList(fromIndex: Int, toIndex: Int): List<Nothing> = throw UnsupportedOperationException()
}

private object NotEmptyListOfAny : MutableList<Any> {
    override fun contains(element: Any): Boolean = true
    override fun indexOf(element: Any): Int = 0
    override fun lastIndexOf(element: Any): Int = 0
    override fun remove(element: Any): Boolean = true

    override val size: Int
        get() = throw UnsupportedOperationException()

    override fun containsAll(elements: Collection<Any>): Boolean = elements.isEmpty()
    override fun isEmpty(): Boolean = throw UnsupportedOperationException()
    override fun get(index: Int): Any = throw UnsupportedOperationException()
    override fun add(element: Any): Boolean = throw UnsupportedOperationException()
    override fun addAll(elements: Collection<Any>): Boolean = throw UnsupportedOperationException()
    override fun addAll(index: Int, elements: Collection<Any>): Boolean = throw UnsupportedOperationException()
    override fun removeAll(elements: Collection<Any>): Boolean = throw UnsupportedOperationException()
    override fun retainAll(elements: Collection<Any>): Boolean = throw UnsupportedOperationException()
    override fun clear(): Unit = throw UnsupportedOperationException()
    override fun set(index: Int, element: Any): Any = throw UnsupportedOperationException()
    override fun add(index: Int, element: Any): Unit = throw UnsupportedOperationException()
    override fun removeAt(index: Int): Any = throw UnsupportedOperationException()
    override fun listIterator(): MutableListIterator<Any> = throw UnsupportedOperationException()
    override fun listIterator(index: Int): MutableListIterator<Any> = throw UnsupportedOperationException()
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<Any> = throw UnsupportedOperationException()
    override fun iterator(): MutableIterator<Any> = throw UnsupportedOperationException()
}

private object EmptyMapOfAnyNothing : Map<Any, Nothing> {
    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true

    override fun containsKey(key: Any): Boolean = false
    override fun containsValue(value: Nothing): Boolean = false
    override fun get(key: Any): Nothing? = null
    override val entries: Set<Map.Entry<Any, Nothing>> get() = null!!
    override val keys: Set<Any> get() = null!!
    override val values: Collection<Nothing> get() = null!!
}

private object EmptyStringMapOfNothing : Map<String, Nothing> {
    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true

    override fun containsKey(key: String): Boolean = false
    override fun containsValue(value: Nothing): Boolean = false
    override fun get(key: String): Nothing? = null
    override val entries: Set<Map.Entry<String, Nothing>> get() = null!!
    override val keys: Set<String> get() = null!!
    override val values: Collection<Nothing> get() = null!!
}

private object NotEmptyMapOfAny : MutableMap<Any, Any> {
    override fun containsKey(key: Any): Boolean = true
    override fun containsValue(value: Any): Boolean = true
    override fun get(key: Any): Any? = Any()
    override fun remove(key: Any): Any? = Any()

    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true
    override fun put(key: Any, value: Any): Any? = throw UnsupportedOperationException()
    override fun putAll(from: Map<out Any, Any>): Unit = throw UnsupportedOperationException()
    override fun clear(): Unit = throw UnsupportedOperationException()
    override val entries: MutableSet<MutableMap.MutableEntry<Any, Any>> get() = null!!
    override val keys: MutableSet<Any> get() = null!!
    override val values: MutableCollection<Any> get() = null!!
}

private object NotEmptyIntMapOfAny : MutableMap<Any, Int> {
    override fun containsKey(key: Any): Boolean = true
    override fun containsValue(value: Int): Boolean = true

    override fun get(key: Any): Int = 1
    override fun remove(key: Any): Int = 1

    override val size: Int get() = 0
    override fun isEmpty(): Boolean = true
    override fun put(key: Any, value: Int): Int? = throw UnsupportedOperationException()
    override fun putAll(from: Map<out Any, Int>): Unit = throw UnsupportedOperationException()
    override fun clear(): Unit = throw UnsupportedOperationException()
    override val entries: MutableSet<MutableMap.MutableEntry<Any, Int>> get() = null!!
    override val keys: MutableSet<Any> get() = null!!
    override val values: MutableCollection<Int> get() = null!!
}

fun box(): String {
    val emptyStrings = EmptyListOfNothing as List<String>
    if (emptyStrings.contains("")) return "fail 1"
    if (emptyStrings.indexOf("") != -1) return "fail 2"
    if (emptyStrings.lastIndexOf("") != -1) return "fail 3"

    val emptyAnys = EmptyListOfNothing as List<Any?>
    if (emptyAnys.contains(null)) return "fail 4"
    if (emptyAnys.indexOf(null) != -1) return "fail 5"
    if (emptyAnys.lastIndexOf(null) != -1) return "fail 6"

    val listAny = NotEmptyListOfAny as MutableList<Any?>
    if (listAny.contains(null)) return "fail 7"
    if (listAny.indexOf(null) != -1) return "fail 8"
    if (listAny.lastIndexOf(null) != -1) return "fail 9"
    if (!listAny.contains("")) return "fail 10"
    if (listAny.indexOf("") != 0) return "fail 11"
    if (listAny.lastIndexOf("") != 0) return "fail 12"
    if (listAny.remove(null)) return "fail 13"
    if (!listAny.remove("")) return "fail 14"

    val emptyMap = EmptyMapOfAnyNothing as Map<Any?, Any?>
    if (emptyMap.get(null) != null) return "fail 15"
    if (emptyMap.containsKey(null)) return "fail 16"
    if (emptyMap.containsValue(null)) return "fail 17"

    val emptyStringMap = EmptyStringMapOfNothing as Map<Any?, Any?>
    if (emptyStringMap.get(null) != null) return "fail 18"
    if (emptyStringMap.containsKey(null)) return "fail 19"
    if (emptyStringMap.containsValue(null)) return "fail 20"

    val mapAny = NotEmptyMapOfAny as MutableMap<Any?, Any?>
    if (mapAny.get(null) != null) return "fail 21"
    if (mapAny.containsKey(null)) return "fail 22"
    if (mapAny.containsValue(null)) return "fail 23"
    if (mapAny.remove(null) != null) return "fail 24"
    if (mapAny.get("") == null) return "fail 25"
    if (!mapAny.containsKey("")) return "fail 26"
    if (!mapAny.containsValue("")) return "fail 27"
    if (mapAny.remove("") == null) return "fail 28"

    val mapInt = NotEmptyIntMapOfAny as MutableMap<Any?, Any?>
    if (mapInt.get(null) != null) return "fail 29"
    if (mapInt.containsKey(null)) return "fail 30"
    if (mapInt.containsValue(null)) return "fail 31"
    if (mapInt.remove(null) != null) return "fail 32"
    if (mapInt.get(1) == null) return "fail 33"
    if (!mapInt.containsKey("")) return "fail 34"
    if (!mapInt.containsValue(3)) return "fail 35"
    if (mapInt.remove("") == null) return "fail 36"

    return "OK"
}

fun main() {
    println(box())
}
