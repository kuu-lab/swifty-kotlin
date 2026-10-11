import ConstructorMark as constructor

@Target(AnnotationTarget.CONSTRUCTOR)
annotation class ConstructorMark(val constructor: String)
@Target(AnnotationTarget.CONSTRUCTOR)
annotation class ComparisonMark(val enabled: Boolean)

open class ConstructorBase(val number: Int)
class AnnotatedSecondary private constructor(val value: Int) {
    @constructor(constructor = "this")
    constructor(): this(7)

    @Deprecated("Use the empty constructor", ReplaceWith("AnnotatedSecondary()"))
    constructor(value: String): this(value.length)
}
class AnnotatedDerived: ConstructorBase {
    @constructor(constructor = "super")
    constructor(): super(9)
}
class AnnotatedComparison {
    @ComparisonMark(1 < 2)
    constructor(number: Int) { check(number == 11) }
}
class AnnotatedAlias {
    @constructor(constructor = "alias")
    constructor(number: Int) { check(number == 13) }
}

@Suppress("DEPRECATION")
fun main() {
    println(AnnotatedSecondary().value)
    println(AnnotatedSecondary("ab").value)
    println(AnnotatedDerived().number)
    AnnotatedComparison(11)
    AnnotatedAlias(13)
}
