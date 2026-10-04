fun linkedFactoryTypes() {
    val set: LinkedHashSet<Int> = linkedSetOf(1, 2, 1)
    val emptySet: LinkedHashSet<String> = linkedSetOf()
    val map: LinkedHashMap<String, Int> = linkedMapOf("a" to 1, "a" to 2)
    val emptyMap: LinkedHashMap<String, Int> = linkedMapOf()
}
