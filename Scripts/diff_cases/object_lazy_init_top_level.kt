import kotlin.io.encoding.Base64
import kotlin.io.encoding.ExperimentalEncodingApi

open class Parent(val value: Int)

object LocalObject : Parent(9) {
    init { println("local init") }
}

class LocalClass {
    companion object {
        init { println("companion init") }
        val value = 12
    }
}

val localObjectValue = LocalObject.value
val localCompanionValue = LocalClass.value

@OptIn(ExperimentalEncodingApi::class)
val importedObjectValue = Base64.Default.encode("foo".encodeToByteArray())

fun main() {
    println(localObjectValue)
    println(localCompanionValue)
    println(importedObjectValue)
}
