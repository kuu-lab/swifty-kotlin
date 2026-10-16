// KUU-2428: infer the receiver type for an unbound generic extension-property reference.
val <T> T.id: T get() = this
fun apply(f: (String) -> String): String = f("OK")

// Controls for direct reads and neighboring callable-reference paths.
val <T> T.directIdentity: T get() = this
val String.fixedIdentity: String get() = this
fun <T> T.genericIdentity(): T = this

fun box(): String {
    if (apply(String::id) != "OK") return "FAIL:unbound-generic-property"
    if ("OK".directIdentity != "OK") return "FAIL:generic-property-read"
    if (apply(String::fixedIdentity) != "OK") return "FAIL:non-generic-property-reference"
    if (apply(String::genericIdentity) != "OK") return "FAIL:generic-function-reference"
    return "OK"
}

fun main() {
    println(box())
}
