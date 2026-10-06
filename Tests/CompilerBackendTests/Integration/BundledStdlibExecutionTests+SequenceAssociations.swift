import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testSequenceAssociationCanonicalImportsAndNamedSelectors() throws {
        try compileAndRunKotlin(
            """
            import kotlin.sequences.associate as seqAssociate
            import kotlin.sequences.associateWith as seqAssociateWith
            import kotlin.sequences.associateWith
            import kotlin.sequences.associateWithTo as seqAssociateWithTo

            fun <T> identity(values: Sequence<T>): Map<T, T> =
                values.seqAssociateWith(valueSelector = { it })

            fun main() {
                println(sequenceOf(1).seqAssociate(transform = { it to it + 1 }))
                println(sequenceOf(1).associateWith(valueSelector = { it + 1 }))
                println(identity(sequenceOf<String?>(null, "a", null)))
                val destination = mutableMapOf<Any?, Any?>("seed" to -1)
                println(sequenceOf(1, 1).seqAssociateWithTo(destination, valueSelector = { it + 1 }) === destination)
                println(destination)
                println(emptySequence<Int>().seqAssociateWith(valueSelector = { it + 1 }))
                println(listOf(1).associate { it to it + 2 })
            }
            """,
            expectedOutput: "{1=2}\n{1=2}\n{null=null, a=a}\ntrue\n{seed=-1, 1=2}\n{}\n{1=3}\n",
            moduleName: "KSP1340CanonicalAssociations"
        )
    }
}
