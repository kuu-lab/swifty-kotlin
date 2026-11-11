@file:OptIn(ExperimentalStdlibApi::class)

private fun printFailure(action: () -> String?) {
    try {
        println(action())
    } catch (exception: IllegalStateException) {
        println(exception.message)
    }
}

private fun readFallbacks() {
    val map = mapOf<String, String?>("null" to null, "value" to "stored")
    var calls = 0
    val fallback = {
        calls += 1
        "fallback-$calls"
    }
    val nullFallback: () -> String? = {
        calls += 1
        null
    }

    println(map.getOrElseIfNull("missing", fallback))
    println(map.getOrElseIfNull("null", fallback))
    println(map.getOrElseIfNull("value", fallback))
    println(map.getOrElseIfNull("missing", nullFallback))
    printFailure { map.getOrElseIfNull("null") { error("getOrElseIfNull failed") } }

    println(map.getOrElseIfMissing("missing", fallback))
    println(map.getOrElseIfMissing("null", fallback))
    println(map.getOrElseIfMissing("value", fallback))
    println(map.getOrElseIfMissing("missing", nullFallback))
    printFailure { map.getOrElseIfMissing("missing") { error("getOrElseIfMissing failed") } }

    println(calls)
    println(map.containsKey("missing"))
    println(map["null"])
}

private fun writeFallbacksIfNull() {
    val map = mutableMapOf<String, String?>("null" to null, "value" to "stored", "failed" to null)
    var calls = 0
    val fallback = {
        calls += 1
        "fallback-$calls"
    }

    println(map.getOrPutIfNull("missing", fallback))
    println(map.getOrPutIfNull("null", fallback))
    println(map.getOrPutIfNull("value", fallback))
    println(map["missing"])
    println(map["null"])
    println(map["value"])

    val insertedNull = map.getOrPutIfNull("new-null") {
        calls += 1
        null
    }
    println(insertedNull)
    println(map.containsKey("new-null"))
    println(map.getOrPutIfNull("new-null", fallback))
    println(map["new-null"])
    println(calls)

    printFailure { map.getOrPutIfNull("failed") { error("getOrPutIfNull failed") } }
    println(map.containsKey("failed"))
    println(map["failed"])
}

private fun writeFallbacksIfMissing() {
    val map = mutableMapOf<String, String?>("null" to null, "value" to "stored")
    var calls = 0
    val fallback = {
        calls += 1
        "fallback-$calls"
    }

    println(map.getOrPutIfMissing("missing", fallback))
    println(map.getOrPutIfMissing("null", fallback))
    println(map.getOrPutIfMissing("value", fallback))
    println(map["missing"])
    println(map["null"])
    println(map["value"])

    val insertedNull = map.getOrPutIfMissing("new-null") {
        calls += 1
        null
    }
    println(insertedNull)
    println(map.containsKey("new-null"))
    println(map.getOrPutIfMissing("new-null", fallback))
    println(map["new-null"])
    println(calls)

    printFailure { map.getOrPutIfMissing("failed") { error("getOrPutIfMissing failed") } }
    println(map.containsKey("failed"))
}

private fun nonLocalReturn(ifNull: Boolean): String {
    val map = mapOf<String, String?>("null" to null)
    if (ifNull) {
        map.getOrElseIfNull("null") { return "getOrElseIfNull returned" }
    } else {
        map.getOrElseIfMissing("missing") { return "getOrElseIfMissing returned" }
    }
    return "fell through"
}

fun main() {
    readFallbacks()
    writeFallbacksIfNull()
    writeFallbacksIfMissing()
    println(nonLocalReturn(true))
    println(nonLocalReturn(false))
}
