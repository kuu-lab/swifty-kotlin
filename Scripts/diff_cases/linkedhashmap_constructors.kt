fun copyFromParameter(source: Map<String, Int>): LinkedHashMap<String, Int> {
    return LinkedHashMap(source)
}

fun main() {
    val withCapacity = LinkedHashMap<String, Int>(8)
    withCapacity["a"] = 1
    withCapacity["b"] = 2
    println(withCapacity.size)
    println(withCapacity)

    val withLoadFactor = LinkedHashMap<String, Int>(8, 0.75f)
    withLoadFactor["x"] = 24
    withLoadFactor["y"] = 25
    println(withLoadFactor.size)
    println(withLoadFactor)

    // Copy constructor from a same-function literal.
    val original = linkedMapOf("k1" to 1, "k2" to 2, "k3" to 3)
    val copyFromLiteral = LinkedHashMap(original)
    copyFromLiteral["k4"] = 4
    println(copyFromLiteral.size)
    println(original.size)
    println(copyFromLiteral)
    println(copyFromLiteral == original)

    // Copy constructor from a map passed in as a function parameter (not a
    // literal the current function can see directly).
    val copyFromParam = copyFromParameter(original)
    println(copyFromParam.size)
    println(copyFromParam)
    println(copyFromParam == original)
}
