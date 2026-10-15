// KUU-2358: pinned Kotlin conformance case plus receiver-substitution controls.
// Original: https://github.com/JetBrains/kotlin/blob/679366a83f99851b42f64795f10ed803ff011c73/compiler/testData/codegen/box/inline/kt67866.kt
inline val <reified T> T.id: T
    get() = (this as Any) as T

fun foo(reference: (String) -> String) = reference("OK")

val <T> T.identity: T get() = this
val <T> T.genericDirect: T get() = this
val String.plainIdentity: String get() = this
inline val String.inlineIdentity: String get() = this

fun <T> T.genericFunction(): T = this
fun String.plainFunction(): String = this

fun box(): String {
    val genericReference: (String) -> String = String::identity
    val plainReference: (String) -> String = String::plainIdentity
    val inlineReference: (String) -> String = String::inlineIdentity
    val genericFunctionReference: (String) -> String = String::genericFunction
    val plainFunctionReference: (String) -> String = String::plainFunction

    return foo(String::id) + "|" + genericReference("OK") + "|" + "OK".genericDirect + "|" + plainReference("OK") + "|" + inlineReference("OK") + "|" + genericFunctionReference("OK") + "|" + plainFunctionReference("OK")
}

fun main() {
    println(box())
}
