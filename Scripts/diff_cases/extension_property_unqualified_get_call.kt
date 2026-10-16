val Array<String>.minimalFirstElement: String get() = get(0)
val Array<String>.explicitFirstElement: String get() = this.get(0)

fun main() {
    val values = arrayOf("OK")
    println(values.minimalFirstElement + ":" + values.explicitFirstElement)
}
