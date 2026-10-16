open class TreeBuilder {
    protected class MyASTNodeWrapper(val value: Int, val start: Int, val end: Int)
    public class PublicWrapper(val value: Int)

    protected open fun createNode(value: Int): MyASTNodeWrapper = MyASTNodeWrapper(value, 0, 1)
}

class InlineBuilder : TreeBuilder() {
    override fun createNode(value: Int): MyASTNodeWrapper = MyASTNodeWrapper(value, 0, 1)
    fun protectedNodeValue(): Int = createNode(10).value
    fun publicNode(): PublicWrapper = PublicWrapper(20)
    fun qualifiedNode(): TreeBuilder.PublicWrapper = TreeBuilder.PublicWrapper(30)
}

class TopLevelBuilder : TreeBuilder() {
    override fun createNode(value: Int): MyASTNodeWrapper = MyASTNodeWrapper(value, 0, 1)
    fun protectedNodeValue(): Int = createNode(11).value
}

class CurrentShadow : TreeBuilder() {
    class MyASTNodeWrapper(val value: Int)
    fun node(): MyASTNodeWrapper = MyASTNodeWrapper(40)
}

class LocalShadow : TreeBuilder() {
    fun value(): Int {
        class MyASTNodeWrapper(val value: Int)
        return MyASTNodeWrapper(50).value
    }
}

fun main() {
    val builder = InlineBuilder()
    println(builder.protectedNodeValue())
    println(builder.publicNode().value)
    println(builder.qualifiedNode().value)
    println(TopLevelBuilder().protectedNodeValue())
    println(CurrentShadow().node().value)
    println(LocalShadow().value())
}
