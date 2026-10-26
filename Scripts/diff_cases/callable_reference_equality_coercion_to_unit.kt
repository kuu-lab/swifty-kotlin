class V { fun target(): String = "" }

fun captureString(function: (V) -> String): Any = function
fun captureUnit(function: (V) -> Unit): Any = function

fun main() {
    val firstStringReference = captureString(V::target)
    val secondStringReference = captureString(V::target)
    val firstUnitReference = captureUnit(V::target)
    val secondUnitReference = captureUnit(V::target)
    println(firstStringReference == secondStringReference)
    println(firstUnitReference == secondUnitReference)
    println(firstStringReference == firstUnitReference)
    println(firstUnitReference == firstStringReference)
    println(firstUnitReference.hashCode() == secondUnitReference.hashCode())
}
