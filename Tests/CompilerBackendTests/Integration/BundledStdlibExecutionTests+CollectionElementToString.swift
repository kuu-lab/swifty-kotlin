import Testing

// Collection toString() implementations render their elements in the runtime
// through runtimeElementToString. That path must preserve the user-defined or
// synthesized toString() registered for each object, including at nested
// List/Set/Map/Pair boundaries.
extension BundledStdlibExecutionTests {
    @Test
    func testCollectionToStringCallsElementOverrides() throws {
        try compileAndRunKotlin(
            """
            class V(val x: Int) {
                override fun toString(): String = "V$x"
            }
            data class D(val x: Int)
            data class W(val l: List<D>, val v: V)
            fun main() {
                println(V(1))
                println(D(1))
                println(listOf(V(1), V(2)))
                println(listOf(D(1), D(2)))
                println(setOf(V(1)))
                println(mapOf("k" to V(1)))
                println(mapOf(V(1) to "k"))
                println(listOf(listOf(V(1))))
                println("${listOf(V(1))}")
                println(listOf(V(1)).joinToString())
                println(W(listOf(D(1)), V(2)))
                println(Pair(V(1), D(2)))
                println(listOf(Pair(V(1), 2)))
            }
            """,
            expectedOutput: """
            V1
            D(x=1)
            [V1, V2]
            [D(x=1), D(x=2)]
            [V1]
            {k=V1}
            {V1=k}
            [[V1]]
            [V1]
            V1
            W(l=[D(x=1)], v=V2)
            (V1, D(x=2))
            [(V1, 2)]

            """
        )
    }
}
