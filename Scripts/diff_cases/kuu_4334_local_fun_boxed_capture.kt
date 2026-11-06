fun main() {
    val unrelated: () -> Int = { 30 }
    fun local(): Int {
        val x = unrelated
        return x()
    }
    println(local())

    val seed = 4
    fun helper(): Int = seed + 1
    val ref: () -> Int = ::helper
    fun localRef(): Int = ref()
    println(localRef())

    class WrongArity(val value: Int)
    val receiverFn: WrongArity.() -> Int = { value * 2 }
    fun localReceiver(): Int {
        val apply = receiverFn
        return apply(WrongArity(21))
    }
    println(localReceiver())
}
