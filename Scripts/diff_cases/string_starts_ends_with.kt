fun main() {
    println("hello".startsWith("he"))
    println("hello".startsWith("lo"))
    println("hello".startsWith(""))
    println("".startsWith(""))
    println("".startsWith("x"))
    println("hello".startsWith("hello"))
    println("hello".startsWith("hello world"))

    println("Hello".startsWith("hell", true))
    println("Hello".startsWith("hell", false))
    println("Hello".startsWith("HELLO", true))

    println("hello".startsWith("ll", 2))
    println("hello".startsWith("lo", 3))
    println("hello".startsWith("LO", 3, true))
    println("hello".startsWith("x", 10))

    println("hello".startsWith('h'))
    println("hello".startsWith('H'))
    println("hello".startsWith('H', true))
    println("".startsWith('h'))

    println("hello".endsWith("lo"))
    println("hello".endsWith("he"))
    println("hello".endsWith(""))
    println("hello".endsWith("hello"))
    println("hello".endsWith("say hello"))

    println("Hello".endsWith("LLO", true))
    println("Hello".endsWith("LLO", false))

    println("hello".endsWith('o'))
    println("hello".endsWith('O'))
    println("hello".endsWith('O', true))
    println("".endsWith('o'))

    println("hello world".startsWith("hello") && "hello world".endsWith("world"))
    println("こんにちは".startsWith("こん"))
    println("こんにちは".endsWith("にちは"))
    println("こんにちは".startsWith("にちは"))
}
