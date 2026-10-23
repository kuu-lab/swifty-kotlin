tailrec fun tailCallInRun(n: Int): Int {
    if (n <= 0) return 0
    run { return tailCallInRun(n - 1) }
}

tailrec fun tailCallInParentheses(n: Int) {
    if (n == 0) return
    return (tailCallInParentheses(n - 1))
}

tailrec fun tailCallInBlockInParentheses(n: Int) {
    return if (n > 0) { (tailCallInBlockInParentheses(n - 1)) } else {}
}

tailrec fun returnInParentheses(n: Int) {
    if (n == 0) return
    (return returnInParentheses(n - 1))
}

tailrec infix fun Int.infixRecursiveCall(n: Int) {
    if (n == 0) return
    val next = n - 1
    return 1 infixRecursiveCall next
}

tailrec fun Int.extensionTailCall(n: Int) {
    if (n == 0) return
    return 1.extensionTailCall(n - 1)
}

fun recursiveInnerFunction() {
    tailrec fun g3(counter: Int) {
        if (counter > 0) { g3(counter - 1) }
    }
    g3(1_000_000)
}

tailrec fun directTailCall(n: Int): Int {
    if (n <= 0) return 0
    return directTailCall(n - 1)
}

fun main() {
    println(tailCallInRun(1_000_000))
    println(directTailCall(1_000_000))
    tailCallInParentheses(1_000_000)
    println("parentheses ok")
    tailCallInBlockInParentheses(1_000_000)
    println("block parentheses ok")
    returnInParentheses(1_000_000)
    println("return parentheses ok")
    1 infixRecursiveCall 1_000_000
    println("infix ok")
    1.extensionTailCall(1_000_000)
    println("extension ok")
    recursiveInnerFunction()
    println("recursive inner function ok")
}
