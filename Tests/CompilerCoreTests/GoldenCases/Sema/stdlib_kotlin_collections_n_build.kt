package golden.sema

fun useBuildList(): List<Int> = buildList(4) {
    add(1)
    add(2)
}

fun useBuildSet(): Set<Int> = buildSet(4) {
    add(1)
    add(1)
}

fun useBuildMap(): Map<String, Int> = buildMap(4) {
    put("a", 1)
    put("a", 2)
}
