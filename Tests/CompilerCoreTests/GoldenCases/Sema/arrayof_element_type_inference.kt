// RF-FIXTURE-002: mixed Int/String/Double arrayOf infers Comparable<*> on Native, without JVM Serializable.
// KUU-3964: the unsteered mixed call is a reified-intersection error (KT-72035),
// so this fixture steers the join through an expected element type instead.

fun arrayOfInts() {
    val ints = arrayOf(1, 2, 3)
    val checked: Array<Int> = ints
}

fun arrayOfStrings() {
    val strings = arrayOf("hello", "world")
    val checked: Array<String> = strings
}

fun arrayOfMixed() {
    val mixed: Array<Comparable<*>> = arrayOf(1, "two", 3.0)
    val checked: Array<Comparable<*>> = mixed
}
