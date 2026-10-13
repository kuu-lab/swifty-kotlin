// KUU-1934: A function-type factory must provide context before raw SAM construction.
// KOTLINC_FLAGS: -Xjdk-release=17
fun interface Operation<T> { fun apply(value: T): Int }
object CharOperation : Operation<Char> { override fun apply(value: Char): Int = value.code }
fun Operation(block: (String) -> Int): Operation<Char> = CharOperation
fun main() { println(Operation { it.length }.apply('a')) }
