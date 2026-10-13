fun main() {
    listOf(1, 2, 3, 4, 5).forEach {
        if (it == 3) return@forEach
        println(it)
    }
    println("after forEach")
    val result = run {
        if (true) return@run "early"
        "late"
    }
    println(result)

    val r = run { return@run 9 }
    println(r)
    println(run { return@run 9 })
    println(run(foo@{ return@foo 7 }))
    println(run { return@run "tail" })
    println(run<Int?> { return@run null })
    println(run { return@run 2147483648L })
    println("x".let { return@let 4 })
    println(with(0) { return@with "w" })
    println(listOf(1, 2).map { return@map it * 2 })
}
