// KUU-4474: bundled kotlinx.serialization.json ships JsonArray/JsonObject
// as public JsonElement subclasses — `is` checks, `when` exhaustiveness,
// List/Map delegation, structural equality and compact JSON toString must
// match the JVM artifact.
import kotlinx.serialization.json.*

fun describe(e: JsonElement): String = when (e) {
    is JsonArray -> "array"
    is JsonObject -> "object"
    JsonNull -> "null"
    is JsonPrimitive -> "primitive"
}

fun main() {
    val arr = JsonArray(listOf(JsonPrimitive(1), JsonPrimitive("x"), JsonNull, JsonArray(listOf(JsonPrimitive(true)))))
    println(arr)
    println("${arr.size}:${arr[0]}:${arr[3]}")
    // "$it" renders through the same toString path; an explicit `it.toString()`
    // on the abstract JsonElement receiver hits KUU-4487 (Any-member vtable
    // slot mismatch), a pre-existing dispatch bug unrelated to this case.
    println(arr.map { "$it" })
    println(arr.contains(JsonNull))
    println(arr.indexOf(JsonPrimitive("x")))

    val obj = JsonObject(mapOf("a" to JsonPrimitive(1), "b" to JsonPrimitive("s"), "c" to JsonNull))
    println(obj)
    println("${obj.size}:${obj["a"]}:${obj.keys}:${obj.values}")
    println(obj.containsKey("b"))
    println(obj.entries.joinToString(",") { "${it.key}=${it.value}" })

    println(obj == JsonObject(mapOf("a" to JsonPrimitive(1), "b" to JsonPrimitive("s"), "c" to JsonNull)))
    println(arr == JsonArray(listOf(JsonPrimitive(1), JsonPrimitive("x"), JsonNull, JsonArray(listOf(JsonPrimitive(true))))))
    println(obj != JsonObject(mapOf("a" to JsonPrimitive(2))))
    println(obj.hashCode() == JsonObject(mapOf("a" to JsonPrimitive(1), "b" to JsonPrimitive("s"), "c" to JsonNull)).hashCode())

    val e: JsonElement = obj
    println(e is JsonObject)
    println(e.jsonObject == obj)
    println(describe(e))
    println(describe(arr))
    println(describe(JsonNull))
    println(describe(JsonPrimitive("p")))

}
