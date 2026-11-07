// EXPECT-ACCEPT
interface ID { fun who(): String = "D" }
open class SCov : ID { override fun who() = "s" }
class Ok : SCov(), ID
interface IAbs { fun q(): String }
class Ok2 : SCov(), IAbs { override fun q() = "q" }
fun main() { println(Ok().who()); println(Ok2().who()) }
