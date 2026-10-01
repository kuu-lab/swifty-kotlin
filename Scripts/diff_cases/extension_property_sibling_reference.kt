// Regression: an unqualified reference to a sibling extension property inside
// another same-receiver extension body (`id` in `label`, `label` in
// `describe`/`describeTwice`) must dispatch to that property's getter on the
// implicit receiver, not read a global slot that is never initialized (which
// surfaced as Int -> 0, String -> null — e.g. Worker.toString printing
// "Worker null").
@JvmInline
value class Box internal constructor(internal val raw: Int)

val Box.id: Int
    get() = raw

val Box.label: String
    get() = "box $id"

fun Box.describe(): String = "desc $label"

fun Box.describeTwice(): String = "$label | $label"

fun main() {
    val b = Box(41)
    println(b.id)
    println(b.label)
    println(b.describe())
    println(b.describeTwice())
}
