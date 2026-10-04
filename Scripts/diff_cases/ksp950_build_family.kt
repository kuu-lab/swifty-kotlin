fun main() {
    val list = buildList(4) {
        add(1)
        add(2)
    }
    println(list)

    val set = buildSet(4) {
        add("a")
        add("a")
        add("b")
    }
    println(set)

    val map = buildMap(4) {
        put("a", 1)
        put("a", 2)
        put("b", 3)
    }
    println(map)

    try {
        buildList(-1) { add(1) }
        println("negative-list-not-thrown")
    } catch (e: IllegalArgumentException) {
        println("negative-list-thrown")
    }

    try {
        buildSet(-1) { add(1) }
        println("negative-set-not-thrown")
    } catch (e: IllegalArgumentException) {
        println("negative-set-thrown")
    }

    try {
        buildMap(-1) { put("a", 1) }
        println("negative-map-not-thrown")
    } catch (e: IllegalArgumentException) {
        println("negative-map-thrown")
    }

    var leaked: MutableList<Int>? = null
    val readOnly = buildList {
        leaked = this
        add(7)
    }
    try {
        leaked!!.add(8)
        println("list-mutated")
    } catch (e: UnsupportedOperationException) {
        println("list-read-only")
    }
    println(readOnly)

    var leakedSet: MutableSet<Int>? = null
    val readOnlySet = buildSet {
        leakedSet = this
        add(9)
    }
    try {
        leakedSet!!.add(10)
        println("set-mutated")
    } catch (e: UnsupportedOperationException) {
        println("set-read-only")
    }
    println(readOnlySet)

    var leakedMap: MutableMap<String, Int>? = null
    val readOnlyMap = buildMap {
        leakedMap = this
        put("x", 1)
    }
    try {
        leakedMap!!.put("y", 2)
        println("map-mutated")
    } catch (e: UnsupportedOperationException) {
        println("map-read-only")
    }
    println(readOnlyMap)

    println(buildList { add(1) } === buildList { add(1) })
    println(buildSet { add(1) } === buildSet { add(1) })
    println(buildMap { put("x", 1) } === buildMap { put("x", 1) })

    try {
        buildList<Int> { throw IllegalStateException("builder failure") }
        println("exception-not-propagated")
    } catch (e: IllegalStateException) {
        println("exception-propagated")
    }
}
