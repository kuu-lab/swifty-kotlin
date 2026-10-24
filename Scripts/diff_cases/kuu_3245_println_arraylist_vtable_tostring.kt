class MyList : ArrayList<Int>() {
    override fun toString(): String = "MyList(${size})"
}

fun main() {
    // ArrayList.toString is `external` (@KsSymbolName kk_list_to_string),
    // whose runtime ABI returns a raw handle. Registered bare in the vtable
    // it mismatched the flat-aggregate slot contract and println spilled
    // heap memory. A bridge now packs the handle into the aggregate.
    val list = ArrayList<Int>()
    list.add(1)
    list.add(2)
    list.add(3)
    println(list)
    println(list.toString())

    val l2: ArrayList<Int> = arrayListOf(5, 6)
    println(l2)

    // A Kotlin override in the same slot must still dispatch correctly.
    val mine = MyList()
    mine.add(3)
    println(mine)

    // Interface-typed receivers take the itable path.
    val poly: MutableList<Int> = list
    println(poly)

    val strs = ArrayList<String>()
    strs.add("x")
    strs.add("yz")
    println(strs)

    val set = LinkedHashSet<Int>()
    set.add(8)
    println(set)

    val map = LinkedHashMap<Int, String>()
    map[1] = "one"
    println(map)
}
