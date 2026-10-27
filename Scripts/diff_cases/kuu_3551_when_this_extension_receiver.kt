// KUU-3551: `is` checks on the extension receiver inside `when (this)` must
// observe the boxed `Any?` value, not a raw enum ordinal. Minimized from
// JetBrains testData codegen/box/when/enumOptimization/kt15806.kt; the
// receiver-boxing fix landed via KUU-3224 (#11319) and this case locks in the
// regression coverage for the `when (this)` form.

enum class Level { O, K }

fun Any?.doIt(): String {
    when (this) {
        is String -> return this
        is Level -> return "L"
        else -> return "fail"
    }
}

// Original kt15806 shape: nested `when (this)` on enum entries after the
// `is Level` smart cast, plus a String receiver taking the `is String` branch.
private fun Any?.doTheThing(): String {
    when (this) {
        is String -> return this
        is Level -> {
            when (this) {
                Level.O -> return Level.O.name
                Level.K -> return Level.K.name
            }
        }
        else -> return "fail"
    }
}

// Non-enum receivers through the same erased `Any?` boundary.
class Box(val v: Int)

fun Any?.kind(): String {
    when (this) {
        is Box -> return "box"
        is Int -> return "int"
        else -> return "other"
    }
}

// Control: the same checks through a value parameter instead of `this`.
fun viaParam(x: Any?): String {
    when (x) {
        is String -> return x
        is Level -> return "L"
        else -> return "fail"
    }
}

fun main() {
    println(Level.K.doIt())
    println(Level.O.doIt())
    println("str".doIt())
    println(42.doIt())
    val n: Any? = null
    println(n.doIt())
    println("O".doTheThing() + Level.K.doTheThing())
    println(Level.O.doTheThing())
    println(Box(7).kind())
    println(5.kind())
    println("x".kind())
    println(viaParam(Level.K))
    println(viaParam("s"))
    println(viaParam(null))
}
