fun failingAssociationBuilder(destination: MutableMap<Int, Int>): Sequence<Int> = sequence<Int> {
    println("emit1:$destination")
    yield(1)
    println("emit2:$destination")
    yield(2)
    println("fail:$destination")
    throw IllegalArgumentException("producer failed after two yields")
}

fun main() {
    // KUU-1212: the original producer failure must preserve the first write.
    val destination = mutableMapOf<Int, Int>()
    try {
        sequence<Int> {
            println("emit1")
            yield(1)
            println("emit2")
            throw IllegalStateException("producer failed")
        }.associateTo(destination) {
            println("key$it")
            it to it
        }
    } catch (error: IllegalStateException) {
        println(error.message)
    }
    println(destination)

    println("before first yield")
    val untouched = mutableMapOf(9 to 90)
    val failure = IllegalArgumentException("before yield")
    val beforeFirst: Sequence<Int> = sequence<Int> { throw failure }
    try {
        beforeFirst.associateTo(untouched) {
            println("unexpected selector")
            it to it
        }
    } catch (error: IllegalStateException) {
        println("wrong exception type")
    } catch (error: IllegalArgumentException) {
        println(error.message)
        println(error === failure)
    }
    println(untouched)

    println("successful repeat traversal")
    val successful = sequence<Int> {
        println("produce1")
        yield(1)
        println("produce2")
        yield(2)
        println("produce3")
        yield(3)
        println("done")
    }
    for (run in 1..2) {
        val completed = mutableMapOf(9 to 90, 1 to -1)
        val result = successful.associateTo(completed) {
            println("transform$it:$completed")
            it % 2 to it * 10
        }
        println(result === completed)
        println(completed)
    }

    println("selector failure")
    val selectorPartial = mutableMapOf(9 to 90)
    try {
        sequence<Int> {
            println("produce1")
            yield(1)
            println("produce2:$selectorPartial")
            yield(2)
            println("unexpected producer resume")
            throw IllegalArgumentException("unexpected producer failure")
        }.associateTo(selectorPartial) {
            println("transform$it")
            if (it == 2) throw IllegalStateException("selector failed")
            it to it * 10
        }
    } catch (error: IllegalStateException) {
        println(error.message)
    }
    println(selectorPartial)

    println("associateByTo key selector")
    val byPartial = mutableMapOf(9 to 90)
    try {
        failingAssociationBuilder(byPartial).associateByTo(byPartial) {
            println("key$it")
            it % 2
        }
    } catch (error: IllegalArgumentException) {
        println(error.message)
    }
    println(byPartial)

    println("associateByTo key and value selectors")
    val byValuePartial = mutableMapOf(9 to 90)
    try {
        failingAssociationBuilder(byValuePartial).associateByTo(
            destination = byValuePartial,
            keySelector = { println("key$it"); 0 },
            valueTransform = { println("value$it"); it * 10 }
        )
    } catch (error: IllegalArgumentException) {
        println(error.message)
    }
    println(byValuePartial)

    println("associateWithTo value selector")
    val withPartial = mutableMapOf(9 to 90)
    try {
        failingAssociationBuilder(withPartial).associateWithTo(
            destination = withPartial,
            valueSelector = { println("value$it"); it * 10 }
        )
    } catch (error: IllegalArgumentException) {
        println(error.message)
    }
    println(withPartial)
}
