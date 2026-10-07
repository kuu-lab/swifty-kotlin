// KUU-1369: `?.` narrows a stable receiver inside its argument expressions.
// `x?.let { x.length }` compiles because the lambda body only runs when the
// receiver is non-null; the narrowing does not escape the call.

class NameBox(val name: String?) {
    // Named `size` on purpose: a member named `length` makes the lambda's
    // receiver read misfire at runtime (pre-existing codegen bug, KUU-1441).
    fun size(): Int? = name?.let { name.length }
}

class Box(val v: String) { fun apply2(block: (String) -> Int): Int = block(v) }

fun param(name: String?) = name?.let { name.length }

fun localVal(): Int {
    val name: String? = "local"
    return name?.let { name.length } ?: -1
}

fun neverReassignedVar(): Int {
    var name: String? = "var"
    return name?.let { name.length } ?: -1
}

fun varReassignedAfter(): Int {
    var name: String? = "x"
    val r = name?.let { name.length }
    name = null
    return r ?: -1
}

fun indexed(name: String?, m: Map<String, Int>) = name?.let { m[name] }

fun nonInlineCallee(box: Box?) = box?.apply2 { box.v.length }

fun main() {
    println(param("abc"))
    println(param(null))
    println(localVal())
    println(neverReassignedVar())
    println(varReassignedAfter())
    println(indexed("k", mapOf("k" to 5)))
    println(indexed(null, mapOf("k" to 5)))
    println(NameBox("x").size())
    println(NameBox(null).size())
    println(nonInlineCallee(Box("box")))
    println(nonInlineCallee(null))
}
