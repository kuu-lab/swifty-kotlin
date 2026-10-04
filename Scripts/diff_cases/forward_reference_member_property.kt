class Forward {
    fun get(): Int = value
    var value = 10
}

class MultipleForwardRefs {
    fun sum(): Int = a + b
    var a = 1
    val b = 2
}

class InterleavedMembers {
    fun first(): Int = second
    var second = 5
    fun third(): Int = second + fourth
    var fourth = 7
}

fun main() {
    println(Forward().get())
    println(MultipleForwardRefs().sum())
    val interleaved = InterleavedMembers()
    println(interleaved.first())
    println(interleaved.third())
}
