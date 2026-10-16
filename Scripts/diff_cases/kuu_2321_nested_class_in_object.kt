// Source port of JetBrains Kotlin compiler/testData/diagnostics/tests/inner/nestedClassInObject.kt
// at commit 679366a83f99851b42f64795f10ed803ff011c73, with execution controls.
object Object {
    class NestedClass {
        fun test() {
            outerFun()
            outerVal
            OuterObject
            OuterClass()
        }
    }

    fun outerFun() {}
    val outerVal = 4
    object OuterObject
    class OuterClass
}

object Owner {
    fun answer(): Int = 1
    fun answerFromBody(): Int = answer()

    class Nested {
        fun answerFromOwner(): Int = answer()
        fun inferredAnswerFromOwner() = answer()
        fun qualifiedAnswer(): Int = Owner.answer()
        val answerAtInitialization: Int = answer()
    }
}

class RegularOwner {
    fun answer(): Int = 2

    class Nested {
        fun qualifiedAnswer(owner: RegularOwner): Int = owner.answer()
    }
}

class InstanceOwner {
    fun answer(): Int = 3

    inner class Nested {
        fun answerFromOwner(): Int = answer()
    }
}

fun box(): String {
    Object.NestedClass().test()
    val nested = Owner.Nested()
    val inner = InstanceOwner().Nested()
    return if (
        nested.answerFromOwner() == 1 &&
        nested.inferredAnswerFromOwner() == 1 &&
        nested.answerAtInitialization == 1 &&
        nested.qualifiedAnswer() == 1 &&
        Owner.answer() == 1 &&
        Owner.answerFromBody() == 1 &&
        RegularOwner.Nested().qualifiedAnswer(RegularOwner()) == 2 &&
        inner.answerFromOwner() == 3
    ) "OK" else "FAIL"
}

fun main() {
    println(box())
    println(Owner.Nested().answerFromOwner())
}
