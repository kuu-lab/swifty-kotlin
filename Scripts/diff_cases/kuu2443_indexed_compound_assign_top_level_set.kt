// KUU-2443: indexed compound assignment must use a visible top-level
// MutableMap.set extension for its write-back.
operator fun <K, V> MutableMap<K, V>.set(key: K, value: V) = put(key, value)

fun boxOriginal(): String {
    val commands: MutableMap<String, String> = HashMap()
    commands["c1"] = "239"
    if (commands["c1"] != "239") return "FAIL"
    commands["c1"] += "932"
    return if (commands["c1"] == "239932") "OK" else "FAIL"
}

fun boxMin(): String {
    val commands: MutableMap<String, String> = HashMap()
    commands["c1"] = "239"
    commands["c1"] += "932"
    return if (commands["c1"] == "239932") "OK" else "FAIL"
}

fun boxControl(): String {
    val commands: MutableMap<String, String> = HashMap()
    commands["c1"] = "239"
    commands["c1"] = commands["c1"] + "932"
    var plain = "239"
    plain += "932"
    return if (commands["c1"] == "239932" && plain == "239932") "OK" else "FAIL"
}

fun main() {
    println("${boxOriginal()}:${boxMin()}:${boxControl()}")
}
