// KOTLINC_FLAGS: -Xcompanion-blocks-and-extensions
// KUU-3823: an enum's `companion {}` block initializers run inside the
// enum's <clinit> after the enum entries, not before them.

var propertyInitLog = ""
private fun initProperty(tag: String, value: String): String { propertyInitLog += tag; return value }

enum class TriggeredByProperty(val value: String) {
    Entry(initProperty("1", "entry"));

    companion { val blockValue = initProperty("2", "block") }
}

fun main() {
    println(TriggeredByProperty.blockValue)
    println(propertyInitLog)
}
