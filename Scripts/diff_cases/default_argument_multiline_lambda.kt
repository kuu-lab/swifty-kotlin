// KUU-1192: declarations inside a multiline default lambda must stay in the parameter group.
fun topRun(value: Int = run {
    var count = 0
    count = count + 1
    count
}): Int = value

class Counter {
    fun next(value: Int = run {
        var count = 0
        count = count + 1
        count
    }): Int = value
}

fun main() {
    println(topRun())
    println(Counter().next())
    println(topRun(5))
    println(Counter().next(6))
    println(withFollowingParameter())
    println(withFollowingParameter(other = 8))
    println(withLambdaDefault())
    println(Primary().value)
    println(Secondary().value)
}

fun withFollowingParameter(value: Int = run {
    val count = run {
        val nested = 3
        nested
    }
    count
}, other: Int = 4): Int = value + other

fun withLambdaDefault(action: () -> Int = {
    var count = 1
    count = count + 1
    count
}): Int = action()

class Primary(val value: Int = run {
    val count = 9
    count
})

class Secondary {
    val value: Int
    constructor(value: Int = kotlin.run {
        val count = 10
        count
    }) {
        this.value = value
    }
}
