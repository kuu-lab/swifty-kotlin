import C.p
import D.q as aliasQ

object C {
    var p: Int = 0
}

object D {
    var q: Int = 0
        set(value) { field = value * 2 }
}

fun box(): String {
    p = 1
    if (p != 1) return "direct import"

    C.p = 2
    if (p != 2) return "qualified setter"

    aliasQ = 3
    if (aliasQ != 6) return "aliased setter"
    if (D.q != 6) return "qualified read"

    return "OK"
}

fun main() {
    println(box())
}
