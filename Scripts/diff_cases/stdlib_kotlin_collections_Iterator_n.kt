private class Probe : Iterator<String?> {
    private var index = 0
    var hasNextCalls = 0
    var nextCalls = 0

    override operator fun hasNext(): Boolean {
        hasNextCalls += 1
        return index < 2
    }

    override operator fun next(): String? {
        nextCalls += 1
        val result = if (index == 0) "first" else null
        index += 1
        return result
    }
}

fun main() {
    val iterator = Probe()
    val same = iterator.iterator()

    println(same === iterator)
    println(same === iterator.iterator())
    println(iterator.hasNextCalls)
    println(iterator.nextCalls)
    println(iterator.hasNext())
    println(iterator.next())
    println(iterator.nextCalls)

    val controlled = Probe()
    for (value in controlled) {
        if (value == "first") continue
        println(value)
        break
    }
    println(controlled.hasNextCalls)
    println(controlled.nextCalls)
}
