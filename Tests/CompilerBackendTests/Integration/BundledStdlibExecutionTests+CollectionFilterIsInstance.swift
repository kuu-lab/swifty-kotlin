import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func filterIsInstanceOnCollectionAndSetReceiversLinks(fromArtifact: Bool) throws {
        try compileAndRunKotlin(
            """
            class C { fun f(): Int = 1 }

            fun viaCollection(xs: Collection<Any?>): List<String> = xs.filterIsInstance<String>()
            fun viaSet(xs: Set<Any?>): List<Int> = xs.filterIsInstance<Int>()
            fun viaIterable(xs: Iterable<Any?>): List<String> = xs.filterIsInstance<String>()

            fun main() {
                println(viaCollection(setOf("a", 1, null, "b")))
                println(viaSet(setOf("a", 1, 2)))
                println(viaIterable(listOf("x", 3)))
                println(C::class.members.filterIsInstance<kotlin.reflect.KFunction<*>>().any { it.name == "f" })
            }
            """,
            expectedOutput: """
            [a, b]
            [1, 2]
            [x]
            true
            """ + "\n",
            moduleName: "CollectionFilterIsInstance",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
