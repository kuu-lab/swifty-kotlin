// KUU-1201: inside a member extension body the dispatch owner contributes its
// inherited members to the implicit receiver tower, so `offset`, `helper()`,
// `this@Derived.offset`, assignments, lambda captures, and inherited member
// extensions must all resolve against the captured dispatch receiver.
open class Base(protected val offset: Int) {
    protected var mutableOffset: Int = 0
    fun helper(): Int = 9
    fun Int.bump(): Int = this + offset
}

class Derived : Base(10) {
    fun Int.add(): Int = this + offset
    fun Int.addHelper(): Int = this + helper()
    fun Int.addLabeled(): Int = this + this@Derived.offset
    fun Int.addBump(): Int = bump() + 1
    fun Int.lambdaProp(): Int = run { this + offset }
    fun Int.lambdaCall(): Int = run { helper() }
    fun Int.assignOnce(): Int {
        mutableOffset = this
        return mutableOffset
    }
    fun Int.compoundOnce(): Int {
        mutableOffset += this
        return mutableOffset
    }

    fun use(): Int {
        println(2.add())
        println(2.addHelper())
        println(2.addLabeled())
        println(3.addBump())
        println(2.lambdaProp())
        println(2.lambdaCall())
        println(5.assignOnce())
        println(5.compoundOnce())
        return 0
    }
}

fun main() {
    Derived().use()
}
