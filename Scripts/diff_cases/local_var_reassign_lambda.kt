fun main() {
    var fib: (Int) -> Int = { 0 }
    fib = { n -> if (n < 2) n else fib(n - 1) + fib(n - 2) }
    println(fib(10))

    lateinit var fact: (Int) -> Int
    fact = { if (it <= 1) 1 else it * fact(it - 1) }
    println(fact(5))

    val fs = mutableMapOf<String, (Int) -> Int>()
    fs["inc"] = { it + 1 }
    val ops = mutableMapOf<String, (Int, Int) -> Int>()
    ops["-"] = { a, b -> a - b }
    println(fs.getValue("inc")(1))
    println(ops.getValue("-")(9, 4))
}
