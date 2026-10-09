fun caughtMessage(action: () -> Unit): String? {
    try {
        action()
    } catch (e: IllegalStateException) {
        return e.message
    }
    return "missing failure"
}

class OverriddenMessage : IllegalStateException("base") {
    override val message: String get() = "override"
}

class NullMessage : IllegalStateException("base") {
    override val message: String? get() = null
}

open class UnrelatedMessage {
    open fun first(): Int = 1
    open fun second(): Int = 2
    open val message: String get() = "unrelated base"
}

class UnrelatedOverride : UnrelatedMessage() {
    override val message: String get() = "unrelated override"
}

fun unrelatedMessage(action: () -> Unit): String {
    val value: UnrelatedMessage = UnrelatedOverride()
    action()
    return value.message
}

fun main() {
    val ordinary = caughtMessage { throw IllegalStateException("ordinary") }
    val overridden = caughtMessage { throw OverriddenMessage() }
    val absent = caughtMessage { throw NullMessage() }
    check(ordinary == "ordinary")
    check(overridden == "override")
    check(absent == null)
    val unrelated = unrelatedMessage { }
    check(unrelated == "unrelated override")
    println(ordinary)
    println(overridden)
    println(absent)
    println(unrelated)
}
