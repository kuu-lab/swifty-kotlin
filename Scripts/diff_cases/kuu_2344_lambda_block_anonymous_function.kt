fun <T> block(block: () -> T): T = block()

fun foo() {}

fun test(): () -> Unit = block { fun(): Unit { foo() } }

fun box(): String {
    val originalFunction = test()
    originalFunction()

    val maker: () -> (() -> Int) = { fun (): Int { return 1 } }
    val namedFunction: () -> Int = {
        fun local() = 2
        local()
    }
    val anonymousFunctionWithReturn: () -> (() -> Int) = { fun(): Int { return 3 } }
    val initializerFunction: () -> Int = fun (): Int { return 4 }
    val nestedLambda: () -> (() -> Int) = { { 5 } }

    return if (
        maker()() == 1
            && namedFunction() == 2
            && anonymousFunctionWithReturn()() == 3
            && initializerFunction() == 4
            && nestedLambda()() == 5
    ) "OK" else "BAD"
}

fun main() {
    println(box())
}
