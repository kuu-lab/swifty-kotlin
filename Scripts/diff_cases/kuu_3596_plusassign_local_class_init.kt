// KUU-3596: a member `var` compound assignment inside a local class's init
// block must resolve its operator against the property's inferred type. The
// local-class path checked `init {}` before member property inference, so
// `y += x` saw the registration-time `Any` placeholder and failed Sema with
// "no viable overload for 'plus'" (named classes check members first).
fun localInitPlusAssign(): Int {
    class A(var x: Int) {
        var y = 0
        init { y += x }
    }
    return A(10).y
}

fun localInitMinusAssign(): Int {
    class A(var x: Int) {
        var y = 20
        init { y -= x }
    }
    return A(5).y
}

fun localInitTimesAssignThis(): Int {
    class A(var x: Int) {
        var y = 3
        init { this.y *= x }
    }
    return A(4).y
}

fun localSecondaryCtorPlusAssign(): Int {
    class A {
        var y = 0
        constructor(x: Int) { y += x }
    }
    return A(12).y
}

class Outer {
    fun localInitInsideMember(): Int {
        class A(var x: Int) {
            var y = 0
            init { y += x }
        }
        return A(11).y
    }
}

fun main() {
    println(localInitPlusAssign())
    println(localInitMinusAssign())
    println(localInitTimesAssignThis())
    println(localSecondaryCtorPlusAssign())
    println(Outer().localInitInsideMember())
}
