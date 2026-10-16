// KUU-2307 regression, based on the Kotlin compiler box fixture below.
// Upstream: https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/jvmStatic/propertyAccess.kt
// Upstream SHA-256: fa5008060ba54bde3b72baa5b0f6192520cd530bda7c1cb4bc1aabb92488672d

var touches = 0
object C { val x = 42 }
fun receiver(): C { touches += 1; return C }
fun receiverRead(): String {
    val value = receiver().x
    return "$value:$touches"
}
fun receiverReadControl(): String {
    receiver()
    val value = C.x
    return "$value:$touches"
}

var holder = ""

fun getA(): A {
    holder += "getA()"
    return A
}

object A {
    val bare = 7
    fun readBare(): Int = bare

    @JvmStatic var a: Int = 1

    var b: Int = 1
        @JvmStatic get

    var c: Int = 1
        @JvmStatic set
}

fun box(): String {
    if (receiverRead() != "42:1") return "fail stored receiver: $touches"
    touches = 0
    if (receiverReadControl() != "42:1") return "fail stored receiver control: $touches"
    if (A.readBare() != 7) return "fail bare property read"

    if (getA().a != 1 || holder != "getA()") return "fail 1: $holder"
    holder = ""

    if (getA().b != 1 || holder != "getA()") return "fail 2: $holder"
    holder = ""
    if (getA().c != 1 || holder != "getA()") return "fail 3: $holder"
    holder = ""

    getA().a = 2
    if (getA().a != 2 || holder != "getA()getA()") return "fail 1: $holder"
    holder = ""

    getA().b = 2
    if (getA().b != 2 || holder != "getA()getA()") return "fail 2: $holder"
    holder = ""

    getA().c = 2
    if (getA().c != 2 || holder != "getA()getA()") return "fail 3: $holder"
    holder = ""

    return "OK"
}

fun main() { print(box()) }
