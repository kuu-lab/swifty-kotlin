// DIFF_JVM
// KUU-3797: a generic constructor call inside a `when` branch whose
// arguments carry no K/V information must still infer its type arguments
// from the sibling branch's type (`this`), the way kotlinc checks all
// branches under one constraint system.
class TN<K, V>(val dataMap: Int, val nodeMap: Int, val buffer: Array<Any?>) {
    val ownedBy: Any? = null
    fun mutableCopy(mutator: Any): TN<K, V> {
        var newDataMap = 11
        var newNodeMap = 22
        val mutableNode = when {
            this.ownedBy == mutator -> this
            else -> {
                val newBuffer = arrayOfNulls<Any>(3)
                TN(newDataMap, newNodeMap, newBuffer)
            }
        }
        return mutableNode
    }
}

class TS<K, V>(val tag: Int) {
    fun pick(o: Any): TS<K, V> {
        val chosen = when (o) {
            is Int -> this
            else -> TS(7)
        }
        return chosen
    }
}

class TI<K, V>(val tag: Int) {
    fun choose(b: Boolean): TI<K, V> {
        val picked = if (b) this else {
            TI(5)
        }
        return picked
    }
}

fun main() {
    val original = TN<String, Int>(0, 0, arrayOfNulls(1))
    val copied = original.mutableCopy(Any())
    println(copied.dataMap)
    println(copied.nodeMap)
    println(copied.buffer.size)
    val picked = TS<String, Int>(1).pick("x")
    println(picked.tag)
    val chosen = TI<String, Int>(1).choose(false)
    println(chosen.tag)
}
