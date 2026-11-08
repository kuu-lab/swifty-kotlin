interface Attr<T>

fun main() {
    val key = object : Attr<String> {}
    val value: Any? = "v"
    val m = buildMap {
        put(key, value)
        run { put(key, value) }
        listOf(1).forEach { put(key, value) }
    }
    println(m.size)

    val l = buildList {
        listOf(1).forEach { add(value) }
    }
    println(l.size)
    println(l[0])

    val xs = mutableListOf(1, 2)
    val applied = buildList {
        xs.apply { add(1) }
        add("s")
    }
    println(applied[0].length)

    val withed = buildList {
        with(xs) { add(1) }
        add("t")
    }
    println(withed[0].length)

    val runned = buildList {
        xs.run { add(1) }
        add("u")
    }
    println(runned[0].length)

    val nested = buildList {
        buildList { add(1) }
        add("w")
    }
    println(nested[0].length)
}
