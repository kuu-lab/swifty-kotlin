// KUU-3914: an extension property referenced unqualified inside a receiver-typed
// lambda (`buildString { ... }`, `with(sb) { ... }`) must resolve against the
// enclosing implicit receiver tower — including when the same file declares
// same-named extensions on other receivers — and the getter must run on the
// captured `this`, not a null global slot (ktor-http URLBuilder.authority).

class URLBuilder(var encodedUser: String = "", var encodedPassword: String = "") {
    var encodedHost: String = ""
}

internal val URLBuilder.encodedUserAndPassword: String
    get() = buildString {
        append(encodedUser)
        if (encodedPassword.isNotEmpty()) {
            append(':')
            append(encodedPassword)
        }
    }

public val URLBuilder.authority: String
    get() = buildString {
        append(encodedUserAndPassword)
        append('@')
        append(encodedHost)
    }

class Outer(val tag: String)

val Outer.other: String
    get() = "other-" + tag

// Two receiver lambdas deep: with(StringBuilder) wraps buildString.
fun Outer.viaWith(): String = with(StringBuilder()) {
    buildString {
        append(other)
        append('|')
        append(tag)
    }
}

// Three receiver lambdas deep: run -> with -> buildString.
fun Outer.viaThreeLevels(): String = run {
    with(StringBuilder()) {
        buildString {
            append(tag)
            append('|')
            append(other)
        }
    }
}

// An extension on the lambda's own receiver type still binds on the lambda's
// receiver (no outer capture is fabricated for it).
val StringBuilder.mirror: String
    get() = toString()

fun Outer.lambdaOwnReceiver(): String = buildString {
    append("x")
    append(mirror)
}

// A nearer receiver's same-named extension shadows the outer one.
class B(val b: String)

val Outer.shade: String
    get() = "shade-Outer-" + tag
val B.shade: String
    get() = "shade-B-" + b

fun Outer.shadowing(): String = with(B("bval")) {
    buildString {
        append(shade)
        append('|')
        append(other)
    }
}

// Explicit this@ on the outer receiver keeps working for member and extension.
fun Outer.qualifiedThis(): String = buildString {
    append(this@qualifiedThis.other)
    append('|')
    append(this@qualifiedThis.tag)
}

fun main() {
    val builder = URLBuilder("user", "pw")
    builder.encodedHost = "host"
    println(builder.authority)
    println(URLBuilder("u2").authority)
    val outer = Outer("tag")
    println(outer.viaWith())
    println(outer.viaThreeLevels())
    println(outer.lambdaOwnReceiver())
    println(outer.shadowing())
    println(outer.qualifiedThis())
}
