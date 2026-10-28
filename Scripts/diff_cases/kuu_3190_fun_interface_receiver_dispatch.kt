// KUU-3190: receiver arguments on fun-interface SAM methods must reach the wrapper implementation.
fun interface SamWithReceiverAndArgument {
    fun Int.accept(value: String): String
}

val samWithReceiverAndArgument = SamWithReceiverAndArgument { value: String -> "OK" }

fun argumentReceiverResult(): String = with(samWithReceiverAndArgument) {
    1.accept("")
}

fun interface DelegatedReceiver {
    fun String.print(): String
}

class DelegatedReceiverAdapter(base: DelegatedReceiver) : DelegatedReceiver by base

fun delegatedReceiverResult(): String = with(DelegatedReceiverAdapter(DelegatedReceiver { this })) {
    "OK".print()
}

fun interface ReceiverWithExtensionProperty {
    fun Int.accept(): String
}

val Int.acceptance: String
    get() = "OK"

val receiverWithExtensionProperty = ReceiverWithExtensionProperty { acceptance }

fun extensionPropertyReceiverResult(): String = with(receiverWithExtensionProperty) {
    1.accept()
}

fun interface ReceiverFunction {
    fun String.foo(): String
}

val receiverFunction = ReceiverFunction { this }

fun useReceiverFunction(value: String, function: ReceiverFunction): String = with(function) {
    value.foo()
}

fun receiverFunctionResult(): String {
    val first = with(receiverFunction) { "OK".foo() }
    if (first != "OK") return "failed 1"
    return useReceiverFunction("O") { this + "K" }
}

fun main() {
    println(argumentReceiverResult())
    println(delegatedReceiverResult())
    println(extensionPropertyReceiverResult())
    println(receiverFunctionResult())
}
