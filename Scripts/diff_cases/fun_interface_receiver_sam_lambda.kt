// KUU-2242 / KUU-3425: A receiver SAM lambda exposes its extension receiver as `this`.
fun interface ReceiverFun { fun String.run(): String }

val receiverFun = ReceiverFun { this }
fun capturedReceiverFun(suffix: String): ReceiverFun = ReceiverFun { this + suffix }

fun box(): String = with(receiverFun) { "OK".run() }
fun capturedBox(): String = with(capturedReceiverFun("!")) { "OK".run() }

fun main() {
    println(box())
    println(capturedBox())
}
