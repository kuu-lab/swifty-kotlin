// KUU-1053: source-declared anonymous overrides must remain delegation targets.
interface J {
    fun f(): Int = 1
}
class G(private val j: J) : J by j
class NamedJ : J {
    override fun f(): Int = 7
}
interface ChildJ : J
class ChildG(j: ChildJ) : ChildJ by j
class OverrideG(j: J) : J by j {
    override fun f(): Int = 99
}

interface Evaluator {
    fun evaluate(value: Int): Int
    fun describe(): String = "default"
}
class Evaluation(delegate: Evaluator) : Evaluator by delegate

interface Properties {
    val answer: Int get() = 1
    var count: Int
}
class PropertyBox(delegate: Properties) : Properties by delegate

fun main() {
    val o = object : J { override fun f(): Int = 7 }
    println(o.f())
    println(G(o).f())
    println(G(object : J {}).f())
    println(G(NamedJ()).f())
    val asJ: J = o
    println(G(asJ).f())
    val wrapped: J = G(o)
    println(wrapped.f())
    println(OverrideG(o).f())

    val child = object : ChildJ { override fun f(): Int = 8 }
    println(ChildG(child).f())
    println(ChildG(object : ChildJ {}).f())

    val offset = 10
    val label = "captured"
    val evaluation = Evaluation(object : Evaluator {
        fun evaluate(value: String): Int = -1
        override fun evaluate(value: Int): Int = offset + value
        override fun describe(): String = label
    })
    println(evaluation.evaluate(3))
    println(evaluation.describe())
    println(Evaluation(object : Evaluator {
        override fun evaluate(value: Int): Int = value * 2
    }).describe())

    val properties = object : Properties {
        override val answer: Int get() = 7
        override var count: Int = 2
    }
    val box = PropertyBox(properties)
    println(box.answer)
    println(box.count)
    box.count = 9
    println(box.count)
    println(properties.count)

    class LocalJ : J { override fun f(): Int = 11 }
    println(G(LocalJ()).f())
}
