// Explicit `this` inside a lambda-with-receiver must denote the lambda's own
// receiver, not the enclosing extension function's receiver.
fun String.ext(): String = buildString { append(this@ext); append("|"); append(this.length) }
fun String.ext4(): String = buildString { append("|"); append(this.length) }
fun String.ext2(): String = buildString { append(this@ext2); append("|"); append(length) }

class C {
    fun f() = buildString { append("ab"); append(this.length) }
}

fun main() {
    println("abc".ext())
    println("abc".ext4())
    println("abc".ext2())
    println(C().f())
}
