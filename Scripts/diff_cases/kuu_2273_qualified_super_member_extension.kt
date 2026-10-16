// KUU-2273: qualified super in a member extension resolves against its dispatch owner.
open class Base {
    open fun f(): String = "base"
}

interface Default {
    fun f(): String = "default"
}

class Direct : Base(), Default {
    override fun f(): String = "direct"
    fun String.extension(): String = super<Base>.f() + "|" + super<Default>.f()
    fun call(): String = "x".extension()
}

open class ABase {
    open fun zzz(): String = "a_base"
}

open class BBase {
    open fun zzz(): String = "b_base"
}

interface BTag {
    fun zzz(): String = "b_tag"
}

class D

class A : ABase() {
    inner class B : BBase(), BTag {
        override fun zzz(): String = "b"
        fun D.foo(): String = super<BBase>.zzz() + "|" + super<BTag>.zzz() + "|" + super@A.zzz()
        fun invoke(d: D): String = d.foo()
    }
}

fun box(): String = if (
    Direct().call() == "base|default" &&
    A().B().invoke(D()) == "b_base|b_tag|a_base"
) "OK" else "FAIL"

fun main() { print(box()) }
