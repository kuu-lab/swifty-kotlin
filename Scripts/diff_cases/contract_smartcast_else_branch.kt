// KUU-3935: a contract smart cast (`require`) inside an `else` branch must
// survive an intervening `check` call — the post-call contract state must not
// re-widen the local to its pre-branch type (okio FileHandle.reposition).
interface S
interface B : S
class RB : B
class C(val tag: Int, var p: Long) : S { var closed = false }

fun reposition(s: S): Long {
    if (s is RB) {
        return -1
    } else {
        require(s is C)
        check(!s.closed)
        s.p = 1
        return s.p
    }
}

fun nestedIf(s: S, flag: Boolean): Long {
    if (s is RB) {
        return -1
    } else {
        require(s is C)
        if (flag) {
            check(!s.closed)
            s.p = 2
        }
        return s.p
    }
}

fun chainedRequire(s: S): Long {
    if (s is RB) {
        return -1
    } else {
        require(s is C)
        require(s.tag == 0)
        s.p = 3
        return s.p
    }
}

fun varLocal(s: S): Long {
    var x: S = s
    if (x is RB) {
        return -1
    } else {
        require(x is C)
        check(!x.closed)
        x.p = 4
        return x.p
    }
}

fun main() {
    println(reposition(C(0, 5)))
    println(nestedIf(C(0, 5), true))
    println(chainedRequire(C(0, 5)))
    println(varLocal(C(0, 5)))
}
