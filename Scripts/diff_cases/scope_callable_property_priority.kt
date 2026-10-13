var getterReads = 0
class Holder(val seed: Int)
val Holder.apply: ((Int) -> Int) -> Int get() {
    getterReads++
    return { transform -> transform(seed) }
}
val Holder.let: ((Int) -> Int) -> Int get() = { transform -> transform(seed) }

class Both(val seed: Int)
val Both.apply: (Both.() -> Unit) -> Int get() = { block -> block(); 16 }

class SameTier(val seed: Int)
val SameTier.apply: (SameTier.() -> Unit) -> Int get() = { 11 }
fun SameTier.apply(block: SameTier.() -> Unit): Int { block(); return 99 }

class WrongArity(val seed: Int)
val WrongArity.apply: () -> Int get() = { 16 }
class WrongInput(val seed: Int)
val WrongInput.apply: (Int) -> Int get() = { 16 }
class WrongLambdaArity(val seed: Int)
val WrongLambdaArity.apply: ((Int, Int) -> Unit) -> Int get() = { 16 }

class Direct(val seed: Int) {
    val apply: ((Int) -> Int) -> Int get() = { transform -> transform(seed) }
}
class PrivateMember(val seed: Int) {
    private val apply: (PrivateMember.() -> Unit) -> Int get() = { 16 }
}

fun main() {
    val holder = Holder(8)
    println(holder.apply { it * 2 })
    println("getters:$getterReads")
    println(holder.let { it + 3 })
    println(Both(4).apply { println(seed) })
    println(SameTier(5).apply { println(seed) })
    println(WrongArity(6).apply { }.seed)
    println(WrongInput(7).apply { }.seed)
    println(WrongLambdaArity(8).apply { }.seed)
    println(Direct(9).apply { it * 2 })
    println(PrivateMember(10).apply { }.seed)
    val absent: Holder? = null
    println(absent?.apply { it * 2 })
    println("getters:$getterReads")
    val present: Holder? = Holder(12)
    println(present?.apply { it + 1 })
    println("getters:$getterReads")
    val apply: Holder.((Int) -> Int) -> Int = { transform -> transform(seed) + 1 }
    println(holder.apply { it * 2 })
    val unrelated: WrongArity.() -> Int = { 30 }
    fun local() {
        val apply = unrelated
        println(WrongArity(6).apply { }.seed)
    }
    local()
}
