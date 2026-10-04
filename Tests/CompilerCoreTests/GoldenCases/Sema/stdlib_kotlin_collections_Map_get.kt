package golden.sema

import kotlin.reflect.KProperty

fun mapGet(map: Map<out String, Int?>, key: String): Int? = map[key]

fun mapGetOrElse(map: Map<String, Int?>, key: String): Int? = map.getOrElse(key) { null }

fun mapGetValue(map: Map<String, Int>, key: String): Int = map.getValue(key)

fun mapDelegate(map: Map<in String, Int>) {
    val delegatedValue: Int by map
    println(delegatedValue)
}
