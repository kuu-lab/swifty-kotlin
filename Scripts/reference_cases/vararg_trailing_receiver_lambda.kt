class ReceiverBuilder { var value: Int = 0 }
fun build(vararg values: Int, action: ReceiverBuilder.() -> Unit = {}): Int {
    val builder = ReceiverBuilder()
    builder.action()
    return builder.value + values.size
}
fun named(vararg values: Int, tag: String, option: Int = 0, action: ReceiverBuilder.() -> Unit = {}): Int {
    val builder = ReceiverBuilder()
    builder.action()
    return builder.value + values.size + option
}
class ReceiverHost {
    fun build(vararg values: Int, action: ReceiverBuilder.() -> Unit = {}): Int {
        val builder = ReceiverBuilder()
        builder.action()
        return builder.value + values.size
    }
}
fun pick(vararg values: Int, action: ReceiverBuilder.(Int) -> Unit = {}): Int {
    val builder = ReceiverBuilder()
    builder.action(41)
    return builder.value + values.size
}
fun pick(vararg values: String, action: ReceiverBuilder.(String) -> Unit = {}): Int {
    val builder = ReceiverBuilder()
    builder.action("string")
    return builder.value + values.size
}
fun main() {
    println(build { value = 17 })
    println(build(1) { value = 23 })
    println(build(1, 2, 3) { value = 31 })
    println(build(action = { value = 37 }))
    println(named(1, tag = "x") { value = 43 })
    println(ReceiverHost().build { value = 47 })
    val host: ReceiverHost? = ReceiverHost()
    println(host?.build(1, 2, 3) { value = 53 })
    println(pick(1, 2, 3) { n: Int -> value = n })
}
