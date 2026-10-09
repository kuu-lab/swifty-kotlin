import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testSequenceFirstCanonicalShortCircuitAndNonLocalReturns() throws {
        try compileAndRunKotlin(
            """
            import kotlin.sequences.first as seqFirst
            import kotlin.sequences.firstOrNull as seqFirstOrNull
            import kotlin.sequences.firstNotNullOf as seqFirstNotNullOf
            import kotlin.sequences.firstNotNullOfOrNull as seqFirstNotNullOfOrNull
            fun pick(): Int { sequenceOf(1).seqFirst { if (it > 0) return it; false }; return -1 }
            fun pickOrNull(): Int { sequenceOf(2).seqFirstOrNull { if (it > 0) return it; false }; return -1 }
            fun pickNotNull(): Int { sequenceOf(3).seqFirstNotNullOf<Int, Int> { if (it > 0) return it; null }; return -1 }
            fun pickNotNullOrNull(): Int { sequenceOf(4).seqFirstNotNullOfOrNull { if (it > 0) return it; null }; return -1 }
            fun <T> first(values: Sequence<T>): T = values.seqFirst()
            fun transformed(values: Sequence<Int>): String =
                values.seqFirstNotNullOf { if (it == 2) "hit" else null }
            fun main() {
                println(sequenceOf(1, 2).map {
                    if (it == 2) throw IllegalStateException("suffix")
                    it
                }.seqFirstNotNullOf { it })
                val iterator = listOf(1, 2).iterator()
                println(iterator.asSequence().seqFirstNotNullOfOrNull { it })
                println(iterator.next())
                println(first(sequenceOf<String?>(null, "tail")))
                println(generateSequence(7) { it }.seqFirst())
                println(pick())
                println(pickOrNull())
                println(pickNotNull())
                println(pickNotNullOrNull())
                println(transformed(sequenceOf(1, 2, 3)))
            }
            """,
            expectedOutput: "1\n1\n2\nnull\n7\n1\n2\n3\n4\nhit\n",
            moduleName: "SequenceFirstCanonicalShortCircuit"
        )
    }
}
