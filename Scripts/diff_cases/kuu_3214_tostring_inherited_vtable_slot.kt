// KUU-3214 / KT-83308: `by` delegation through a private-constructor
// abstract class plus a deep interface hierarchy returned null from a
// virtual `toString()` call. Any-slot calls must follow the ABI of the
// registered implementation: flat String for Kotlin overrides, raw handles
// for the runtime fallback.
interface Node

internal class NodeImpl : Node

interface BsonNode : Node {
    override fun toString(): String
}

abstract class AbstractBsonNode private constructor(
    private val node: NodeImpl,
) : Node by node, BsonNode {

    constructor() : this(NodeImpl())

    final override fun toString(): String = "OK"
}

interface CompoundNode<N : Node>

interface CompoundBsonNode : BsonNode, CompoundNode<BsonNode>

abstract class AbstractCompoundBsonNode() : AbstractBsonNode(), CompoundBsonNode

//------

interface ValueOperators

interface ValueAccumulators<From : Any, Into : Any> : ValueOperators, CompoundBsonNode

interface ArithmeticValueAccumulators<From : Any, Into : Any> : ValueAccumulators<From, Into>

interface AggregationOperators : ValueOperators

interface AccumulationOperators<From : Any, Into : Any> : ValueAccumulators<From, Into>,
    AggregationOperators,
    ArithmeticValueAccumulators<From, Into>

internal class AccumulationOperatorsImpl<From : Any, Into : Any>(
) : AbstractCompoundBsonNode(),
    AccumulationOperators<From, Into>

//------

internal fun <Document : Any, Out : Any> group() = AccumulationOperatorsImpl<Document, Out>()

open class KUU3214Base {
    override fun toString(): String = "base"
}

open class KUU3214Child : KUU3214Base() {
    override fun toString(): String = "child"
}

class KUU3214Leaf : KUU3214Child()

fun box(): String {
    return group<String, String>().toString()
}

fun describe(b: KUU3214Base): String = b.toString()

fun main() {
    println(box())
    println(KUU3214Leaf().toString())
    println(describe(KUU3214Child()))
    println(describe(KUU3214Base()))
}
