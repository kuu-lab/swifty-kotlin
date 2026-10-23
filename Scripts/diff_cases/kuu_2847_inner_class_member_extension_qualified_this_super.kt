// KUU-2847: qualified this and super in an inner class member extension use
// the dispatch receiver for the inner class, while bare this remains the
// extension receiver.
open class ABase {
    open fun zzz(): String = "a_base"
}

open class BBase {
    open fun zzz(): String = "b_base"
}

class D {
    val z = "d"
}

class A : ABase() {
    val z = "a"
    override fun zzz(): String = "a"

    inner class B : BBase() {
        val z = "b"
        override fun zzz(): String = "b"

        fun D.foo(): String {
            if (this@A.z != "a") return "Fail1"
            if (this@B.z != "b") return "Fail2"
            if (super@A.zzz() != "a_base") return "Fail3"
            if (super<BBase>.zzz() != "b_base") return "Fail4"
            if (super@B.zzz() != "b_base") return "Fail5"
            if (this@A.zzz() != "a") return "Fail6"
            if (this@B.zzz() != "b") return "Fail7"
            if (this.z != "d") return "Fail8"
            return "OK"
        }

        fun bar(d: D): String = d.foo()
    }
}

fun main() {
    println(A().B().bar(D()))
}
