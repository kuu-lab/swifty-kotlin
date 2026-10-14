// KUU-2056: Resolve inferred object property dependencies before earlier consumers.
class Consumer { fun read(): Int = Chain.value }
object Chain { val value = Later.value + 1 }
object Later { val value = 41 }
fun main() { println(Consumer().read()) }
