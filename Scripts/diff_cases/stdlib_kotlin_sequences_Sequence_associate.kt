import kotlin.sequences.associate as seqAssociate
import kotlin.sequences.associateBy as seqAssociateBy
import kotlin.sequences.associateByTo as seqAssociateByTo
import kotlin.sequences.associateTo as seqAssociateTo
import kotlin.sequences.associateWith as seqAssociateWith
import kotlin.sequences.associateWith
import kotlin.sequences.associateWithTo as seqAssociateWithTo

class ThrowingSequence : Sequence<Int> {
    override fun iterator(): Iterator<Int> = object : Iterator<Int> {
        private var state = 0

        override fun hasNext(): Boolean = state < 2

        override fun next(): Int {
            if (state == 1) throw IllegalStateException("next failed")
            state += 1
            return 7
        }
    }
}

fun main() {
    // encounter order + last-write-wins on duplicate keys
    println(sequenceOf("a" to 1, "b" to 2, "a" to 3).seqAssociate { it })

    println(sequenceOf("a", "bb", "a").seqAssociateBy(keySelector = { it }))
    println(sequenceOf("a", "bb", "a").seqAssociateBy(keySelector = { it }, valueTransform = { it.length }))

    // supertype-keyed destinations exercise the `in` projections on M
    val byToDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val byToResult = sequenceOf("a", "bb").seqAssociateByTo(byToDestination) { it }
    println(byToResult === byToDestination)
    println(byToDestination)

    val byToTransformedDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val byToTransformedResult = sequenceOf("a", "bb").seqAssociateByTo(
        byToTransformedDestination,
        { it },
        { it.length }
    )
    println(byToTransformedResult === byToTransformedDestination)
    println(byToTransformedDestination)

    val toDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val toResult = sequenceOf("a", "bb").seqAssociateTo(toDestination) {
        Pair(it, it.length)
    }
    println(toResult === toDestination)
    println(toDestination)

    println(sequenceOf("a", "bb", "a").seqAssociateWith(valueSelector = { it.length }))

    val withToDestination = mutableMapOf<Any?, Any?>("seed" to -1)
    val withToResult = sequenceOf("a", "bb").seqAssociateWithTo(
        destination = withToDestination,
        valueSelector = { it.length }
    )
    println(withToResult === withToDestination)
    println(withToDestination)

    println(emptySequence<String>().seqAssociate { it to it.length })

    var keyCalls = 0
    sequenceOf(1, 2, 3).seqAssociateBy {
        keyCalls += 1
        it
    }
    println(keyCalls)

    try {
        ThrowingSequence().seqAssociate { it to it }
        println("no-throw")
    } catch (error: IllegalStateException) {
        println(error.message)
    }

    println(nullableAssociations(sequenceOf<String?>(null, "a", null)))
    println(listOf(1, 2).associate { it to it + 1 })
    println(sequenceOf(1).associateWith(valueSelector = { it + 1 }))

    val partial = mutableMapOf<Any?, Any?>("seed" to -1)
    try {
        sequenceOf(1, 2, 3).seqAssociateByTo(
            destination = partial,
            keySelector = { println("key$it"); it },
            valueTransform = {
                println("value$it")
                if (it == 2) throw IllegalStateException("selector failed")
                it + 10
            }
        )
    } catch (error: IllegalStateException) {
        println(error.message)
    }
    println(partial)

    val iteratorPartial = mutableMapOf<Int, Int>()
    try {
        ThrowingSequence().seqAssociateTo(iteratorPartial) { it to it }
    } catch (error: IllegalStateException) {
        println(error.message)
    }
    println(iteratorPartial)

    var emptyCalls = 0
    val emptyDestination = mutableMapOf<Any?, Any?>(null to null)
    println(emptySequence<String?>().seqAssociateWithTo(emptyDestination, valueSelector = {
        emptyCalls += 1
        it
    }) === emptyDestination)
    println(emptyCalls)
    println(emptyDestination)
}

fun <T> nullableAssociations(values: Sequence<T>): Map<T, T> =
    values.seqAssociateWith(valueSelector = { it })
