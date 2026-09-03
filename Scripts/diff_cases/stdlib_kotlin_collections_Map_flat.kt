fun main() {
    val source = mapOf("a" to 1, "x" to 2)

    val iterableDestination = mutableListOf<Any>("prefix")
    var iterableCalls = 0
    val iterableResult: MutableList<Any> = source.flatMapTo(iterableDestination) {
        iterableCalls += 1
        listOf(it.key, it.value, "iterable")
    }
    println(iterableResult === iterableDestination)
    println(iterableCalls)
    println(iterableDestination)

    val sequenceDestination = mutableListOf<Any>("prefix")
    var sequenceCalls = 0
    val sequenceResult: MutableList<Any> = source.flatMapTo(sequenceDestination) {
        sequenceCalls += 1
        sequenceOf(it.key, it.value, "sequence").constrainOnce()
    }
    println(sequenceResult === sequenceDestination)
    println(sequenceCalls)
    println(sequenceDestination)

    val emptyDestination = mutableListOf<Any?>("prefix")
    val emptyResult = emptyMap<String?, Int?>().flatMapTo(emptyDestination) { listOf("unseen") }
    println(emptyResult === emptyDestination)
    println(emptyDestination)

    val nullableSource = mapOf<String?, Int?>(null to null)
    val nullableDestination = mutableListOf<Any?>("prefix")
    val nullableResult: MutableList<Any?> = nullableSource.flatMapTo(nullableDestination) {
        listOf(it.key, it.value, null)
    }
    println(nullableResult === nullableDestination)
    println(nullableDestination)

    val nullableSequenceDestination = mutableListOf<Any?>("prefix")
    val nullableSequenceResult: MutableList<Any?> = nullableSource.flatMapTo(nullableSequenceDestination) {
        sequenceOf<Any?>(it.key, it.value, null).constrainOnce()
    }
    println(nullableSequenceResult === nullableSequenceDestination)
    println(nullableSequenceDestination)

    var iterableUsed = false
    val oneShotIterable = object : Iterable<Any?> {
        override fun iterator(): Iterator<Any?> {
            if (iterableUsed) throw IllegalStateException("iterable reused")
            iterableUsed = true
            return listOf<Any?>("custom", null).iterator()
        }
    }
    val customDestination = mutableListOf<Any?>("prefix")
    val customResult = nullableSource.flatMapTo(customDestination) { oneShotIterable }
    println(customResult === customDestination)
    println(customDestination)

    val exceptionDestination = mutableListOf<Int>()
    var exceptionCalls = 0
    try {
        source.flatMapTo(exceptionDestination) {
            exceptionCalls += 1
            if (it.key == "x") throw IllegalStateException("boom")
            listOf(it.value)
        }
    } catch (exception: IllegalStateException) {
        println(exceptionCalls)
        println(exceptionDestination)
        println(exception.message)
    }
}
