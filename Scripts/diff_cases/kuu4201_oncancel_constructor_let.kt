typealias OnCancellationConstructor = (select: Int, param: Any?, internalResult: Any?) ->
    (cause: Any?, handled: Boolean, resumed: Any?) -> Unit

class Holder(val onUndeliveredElement: (() -> Unit)?) {
    val ctor: OnCancellationConstructor? = onUndeliveredElement?.let {
        { select: Int, _: Any?, element: Any? ->
            { _, _, _ ->
                if (element != null) onUndeliveredElement()
            }
        }
    }
}

fun main() {
    val h = Holder { println("undelivered") }
    h.ctor?.invoke(1, null, "x")?.invoke(null, false, null)
    println(h.ctor != null)
}
