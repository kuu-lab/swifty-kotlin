interface Input { fun value(offset: Int): Int }
class Impl : Input { override fun value(offset: Int): Int = offset }
class Wrapped(original: Input) : Input by original
fun main() { println(Wrapped(Impl()).value(offset = 3)) }
