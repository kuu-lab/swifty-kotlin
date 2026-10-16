// KUU-2242: A receiver SAM lambda exposes its extension receiver as `this`.
fun interface ReceiverFun { fun String.run(): String }

val receiverFun = ReceiverFun { this }

fun box(): String = with(receiverFun) { "OK".run() }

fun main() { println(box()) }
