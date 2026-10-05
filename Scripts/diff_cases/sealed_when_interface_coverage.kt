sealed class Grammar
interface SimpleGrammar { val g: Grammar }
class MaybeG(override val g: Grammar) : Grammar(), SimpleGrammar
class ManyG(override val g: Grammar) : Grammar(), SimpleGrammar
class SeqG(val gs: List<Grammar>) : Grammar()
class OrG(val gs: List<Grammar>) : Grammar()

fun classify(g: Grammar) = when (g) {
    is SeqG -> 1
    is OrG -> 2
    is SimpleGrammar -> 3
}

fun Grammar.grouped() = when (this) {
    is SeqG, is OrG -> 1
    is SimpleGrammar -> 2
}

interface Tag
interface ChildTag : Tag
open class Tagged : ChildTag
sealed interface Node
class Leaf : Tagged(), Node
object End : Node
class Holder(val node: Node)

fun classifyHolder(holder: Holder) = when (holder.node) {
    is Tag -> 10
    End -> 20
}

fun classifyNullable(node: Node?) = when (node) {
    is Tag -> 10
    End -> 20
    null -> 30
}

fun main() {
    val seq = SeqG(emptyList())
    val either = OrG(emptyList())
    val maybe = MaybeG(seq)
    val many = ManyG(either)
    println(classify(seq))
    println(classify(either))
    println(classify(maybe))
    println(classify(many))
    println(seq.grouped())
    println(either.grouped())
    println(maybe.grouped())
    println(many.grouped())
    println(classifyHolder(Holder(Leaf())))
    println(classifyHolder(Holder(End)))
    println(classifyNullable(Leaf()))
    println(classifyNullable(End))
    println(classifyNullable(null))
}
