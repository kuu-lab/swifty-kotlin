import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func collectionCopyConstructorDelegationPopulatesSubclass(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            class CopyList<E>(initial: Collection<E>) : ArrayList<E>(initial)
            class CopyLinkedSet<E>(initial: Collection<E>) : LinkedHashSet<E>(initial)
            class CopyTreeSet<E : Comparable<E>>(initial: Collection<E>) : java.util.TreeSet<E>(initial)
            class CopyHashMap<K, V>(initial: Map<K, V>) : HashMap<K, V>(initial)
            class CopyLinkedMap<K, V>(initial: Map<K, V>) : LinkedHashMap<K, V>(initial)

            fun main() {
                val list = CopyList(listOf("a", "b"))
                println(list.size)
                println(list[1])
                list.add("c")
                println(list.size)

                val set = CopyLinkedSet(listOf("x", "y"))
                println(set.size)
                println(set.contains("y"))

                val tree = CopyTreeSet(listOf("b", "a"))
                println(tree.size)
                println(tree.first())

                val map = CopyHashMap(mapOf("k" to 1, "j" to 2))
                println(map.size)
                println(map["j"])
                map["i"] = 3
                println(map.size)

                val linkedMap = CopyLinkedMap(mapOf("m" to 4))
                println(linkedMap.size)
                println(linkedMap["m"])
            }
            """,
            expectedOutput: "2\nb\n3\n2\ntrue\n2\na\n2\n2\n3\n1\n4\n",
            moduleName: "KCollectionCopyCtorDelegation",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
