// KUU-2925: A generic call using the builder receiver in the alternate branch
// must not corrupt the PCLA receiver used by the successful yield branch.
class Buildee<CT> {
    var r: CT? = null
    fun yield(arg: CT) {
        r = arg
    }
}

fun <FT> build(instructions: Buildee<FT>.() -> Unit): Buildee<FT> {
    return Buildee<FT>().apply(instructions)
}

class Logger {
    fun error() {
        throw RuntimeException("")
    }
}

fun <T> logger(arg: T): Logger = Logger()

fun main() {
    val b = build {
        if ("".hashCode() == 0) {
            yield("OK")
        } else {
            logger(this).error()
        }
    }
    println(b.r ?: "fail")
}
