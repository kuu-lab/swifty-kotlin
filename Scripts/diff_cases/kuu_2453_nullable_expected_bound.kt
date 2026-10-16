// Based on JetBrains Kotlin v2.3.10 compiler/testData/codegen/box/inference/ifWithAssignmentAndNothingBranch.kt.
// Apache-2.0; pinned at commit 679366a83f99851b42f64795f10ed803ff011c73.
fun <T : Any> materialize(): T {
    return "OK" as T
}

var b = true

fun foo(x: String): String = x
fun foo(x: Int): Int = x

fun box(): String {
    var x: String? = null

    x = if (b) materialize() else throw Exception()

    return foo(x)
}

fun direct(): String? = materialize()

fun main() {
    println(box())
    println(direct())
}
