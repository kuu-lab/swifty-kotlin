fun <T> evaluate(action: () -> T): T = action()

class LambdaReceiver {
    fun <T> visit(value: Int, action: (Int) -> T): T = action(value)
}

fun <T> Int.transform(action: (Int) -> T): T = action(this)

fun main() {
    listOf(1).forEach lit@{ println(it) }
    listOf(1, 2, 3).forEach lit@{
        if (it == 2) return@lit
        println(it)
    }
    listOf(4, 5).forEach() lit@{ println(it) }
    println(listOf(1, 2).map m@{ value -> value * 2 })
    println(listOf(1, 2).map<Int, Int> m@{ value -> value + 3 })
    println(listOf(1, 2).map<Int, Int>() m@{ value -> value + 4 })
    println(listOf(1, 2).map m@{
        if (it == 1) return@m 10
        it * 10
    })
    println(listOf(1, 2).map outer@{ value ->
        evaluate inner@{ return@inner value + 10 }
    })

    val present: List<Int>? = listOf(6, 7)
    val absent: List<Int>? = null
    var calls = 0
    present?.forEach safe@{ calls++; println(it) }
    absent?.forEach safe@{ calls++; println(it) }
    println(present?.map<Int, Int> safe@{ it * 3 })
    println(absent?.map<Int, Int>() safe@{ calls++; it * 3 })
    println(calls)

    println(LambdaReceiver().visit(8) member@{ return@member it + 1 })
    println(LambdaReceiver().visit<Int>(9) member@{ it + 1 })
    println(10.transform extension@{ it + 1 })
    println(11.transform<Int>() extension@{ return@extension it + 1 })
    println(evaluate global@{ return@global 13 })
    println(evaluate() global@{ 14 })
    println(evaluate<Int> global@{ 15 })
    println(evaluate<Int>() global@{ 16 })
    listOf(17).forEach `visit label`@{ println(it) }

    listOf(18).forEach { println(it) }
    listOf(19).forEach({ println(it) })
}
