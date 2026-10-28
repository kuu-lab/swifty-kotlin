open class PsiElement { open val parent: PsiElement get() = this }
class Child(override val parent: PsiElement) : PsiElement()

fun widen(element: PsiElement): String {
    if (element is Child) {
        var parent = element
        parent = parent.parent
    }
    return "OK"
}

fun box(): String = widen(Child(PsiElement()))

fun main() {
    println(box())
}
