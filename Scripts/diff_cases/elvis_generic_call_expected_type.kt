// DIFF_JVM
// JetBrains/Kotlin compiler/testData/codegen/box/elvis/kt6694ExactAnnotationForElvis.kt
// Pinned to 679366a83f99851b42f64795f10ed803ff011c73.
interface PsiElement {
    fun <T: PsiElement> findChildByType(i: Int): T? =
            if (i == 42) JetOperationReferenceExpression() as T else throw Exception()
}
interface JetSimpleNameExpression : PsiElement {
    fun getReferencedNameElement(): PsiElement
}
class JetOperationReferenceExpression : JetSimpleNameExpression {
    override fun getReferencedNameElement() = this
}
class JetLabelReferenceExpression : JetSimpleNameExpression {
    public override fun getReferencedNameElement(): PsiElement =
            findChildByType(42) ?: this
}
fun box(): String {
    val element = JetLabelReferenceExpression().getReferencedNameElement()
    return if (element is JetOperationReferenceExpression) "OK" else "fail"
}

interface Node {
    fun <T : Node> child(code: Int): T? = null
}
class Branch : Node {
    fun parent(): Node = child(42) ?: this
    fun explicitParent(): Node = child<Node>(42) ?: this
    fun directParent(): Node? = child(42)
}
fun minimalBox(): String {
    val branch = Branch()
    return if (branch.parent() === branch && branch.explicitParent() === branch && branch.directParent() == null) "OK" else "fail"
}

fun main() {
    println(if (box() == "OK" && minimalBox() == "OK") "OK" else "fail")
}
