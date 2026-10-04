fun main() {
    // contentToString: numeric, string, empty
    println(arrayOf(1, 2, 3).contentToString())
    println(arrayOf("a", "b", "c").contentToString())
    println(emptyArray<Int>().contentToString())

    // contentToString with null elements (via arrayOfNulls)
    val withNulls = arrayOfNulls<String>(3)
    withNulls[0] = "x"
    withNulls[2] = "z"
    println(withNulls.contentToString())

    // copyOf(): full copy
    val src = arrayOf(1, 2, 3)
    println(src.copyOf().toList())

    // copyOf(newSize): truncation and expansion (expansion pads with null)
    println(src.copyOf(2).toList())
    println(src.copyOf(5).toList())

    // copyOf() independence: mutating the copy leaves the original intact
    val copy = src.copyOf()
    copy[0] = 99
    println(src.toList())
    println(copy.toList())

    // Single element and empty receiver
    println(arrayOf("only").copyOf().toList())
    println(emptyArray<Int>().copyOf().toList())
}
