var escapedList: MutableList<Int>? = null
var escapedMap: MutableMap<Int, String>? = null
fun result(label: String, action: () -> Unit) {
    try { action(); println(label + "=OK") }
    catch (failure: Throwable) { println(label + "=" + failure::class.simpleName) }
}
fun leaveList(): Int {
    buildList<Int> { escapedList = this; add(11); return 7 }
    return -1
}
fun leaveMap(): Int {
    buildMap<Int, String> { escapedMap = this; put(11, "eleven"); return 8 }
    return -1
}
fun main() {
    val numbers = buildList { add(1); add(2) }
    val labels = buildMap { put(1, "one"); put(2, "two"); put(1, "ONE") }
    println(numbers); println(labels)
    val assigned: Int
    val built = buildList<Int> { assigned = 12; escapedList = this; add(3); add(4) }
    println(assigned); println(built)
    println(built === escapedList)
    result("list-add") { escapedList!!.add(5) }
    result("list-set") { escapedList!![0] = 5 }
    result("list-remove") { escapedList!!.remove(99) }
    result("list-clear") { escapedList!!.clear() }
    println(built)
    val mapped = buildMap<Int, String>(capacity = 2) { escapedMap = this; put(3, "three") }
    println(mapped); println(mapped === escapedMap)
    result("map-put") { escapedMap!!.put(4, "four") }
    result("map-remove") { escapedMap!!.remove(99) }
    result("map-clear") { escapedMap!!.clear() }
    println(mapped)
    var called = 0
    result("negative-list") { buildList<Int>(-1) { called++ } }
    result("negative-map") { buildMap<Int, String>(-1) { called++ } }
    println(called)
    println(buildList<Int>(0) { add(6); return@buildList; add(9) })
    println(buildMap<Int, String>(0) { put(6, "six"); return@buildMap; put(9, "nine") })
    result("throw-list") { buildList<Int> { escapedList = this; add(9); throw IllegalStateException("stop") } }
    escapedList!!.add(10); println(escapedList)
    result("throw-map") { buildMap<Int, String> { escapedMap = this; put(9, "nine"); throw IllegalStateException("stop") } }
    escapedMap!!.put(10, "ten"); println(escapedMap)
    println(leaveList()); escapedList!!.add(12); println(escapedList)
    println(leaveMap()); escapedMap!!.put(12, "twelve"); println(escapedMap)
    println(buildList<Int> { } == emptyList<Int>())
    println(buildMap<Int, String> { } == emptyMap<Int, String>())
}
