import kotlin.reflect.KTypeParameter

open class GenericBase<T>
class GenericChild<U : Number> : GenericBase<U>()

class Enclosing() {
    class Nested
    inner class Inner

    fun methodOwner() {
        class LocalInMethod
        val localClass = LocalInMethod::class.java
        println(localClass.getEnclosingClass() == Enclosing::class.java)
        println(localClass.getEnclosingMethod()?.getName())
        println(localClass.getEnclosingConstructor() == null)
        println(localClass.getDeclaringClass() == null)
    }

    constructor(marker: Boolean) : this() {
        class LocalInConstructor
        val localClass = LocalInConstructor::class.java
        println(localClass.getEnclosingClass() == Enclosing::class.java)
        println(localClass.getEnclosingConstructor() != null)
        println(localClass.getEnclosingMethod() == null)
        println(localClass.getDeclaringClass() == null)
    }
}

fun main() {
    println(Enclosing.Nested::class.java.getEnclosingClass() == Enclosing::class.java)
    println(Enclosing.Nested::class.java.getDeclaringClass() == Enclosing::class.java)
    println(Enclosing.Inner::class.java.getEnclosingClass() == Enclosing::class.java)
    Enclosing().methodOwner()
    Enclosing(true)

    val declaredParameter = GenericChild::class.typeParameters.single()
    val supertypeClassifier = GenericChild::class.supertypes.single().arguments.single().type?.classifier
    println(supertypeClassifier is KTypeParameter)
    if (supertypeClassifier is KTypeParameter) {
        check(supertypeClassifier.upperBounds.single().classifier == Number::class)
        check(declaredParameter.upperBounds.single().classifier == Number::class)
        println(supertypeClassifier.name)
        println(supertypeClassifier.variance)
        println(supertypeClassifier.isReified)
        println(declaredParameter == supertypeClassifier)
    }
}
