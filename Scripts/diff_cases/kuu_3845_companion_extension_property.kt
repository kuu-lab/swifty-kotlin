// KOTLINC_FLAGS: -Xcompanion-blocks-and-extensions
// KUU-3845: a top-level `companion val/var T.x` emits a stored property in
// the target's companion scope — storage, implicit accessors, and the
// initializer must all be generated or reads fail to link.
class A
companion val A.compExtVal: String = "extVal"
companion var A.compExtVar: Int = 1
companion val A.compExtComputed: String get() = "extComputed"
companion fun A.compExtFun(): String = "extFun"

class B {
    companion {
        val blockVal = "blockVal"
    }
}
companion val B.compExtValB: String = "bExtVal"

class C {
    companion object {
        val objVal = "objVal"
    }
}
companion val C.compExtValC: String = "cExtVal"

fun main() {
    println(A.compExtVal)
    println(A.compExtVar)
    println(A.compExtComputed)
    println(A.compExtFun())
    println(B.compExtValB)
    println(B.blockVal)
    println(C.compExtValC)
    println(C.objVal)
}
