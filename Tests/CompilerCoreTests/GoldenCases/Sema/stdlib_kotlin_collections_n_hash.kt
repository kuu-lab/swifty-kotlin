fun probe() {
    val emptyMap: HashMap<String?, Int?> = hashMapOf()
    val map = hashMapOf(null to null, "a" to 1, "a" to 2)
    val spreadMap = hashMapOf<String, Int>(*arrayOf("b" to 3))

    val emptySet: HashSet<String?> = hashSetOf()
    val set = hashSetOf(null, null, "x")
    val spreadSet = hashSetOf<String>(*arrayOf("y", "y"))

    println(emptyMap.size + map.size + spreadMap.size)
    println(emptySet.size + set.size + spreadSet.size)
}
