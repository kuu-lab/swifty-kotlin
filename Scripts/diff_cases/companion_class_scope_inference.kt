class A {
    val initialSize = xs.size
    val initialCallSize = getXs().size
    fun f() = xs.size
    fun g() = getXs().size
    fun h() = Companion.xs.size
    fun i() = A.xs.size
    fun textLength() = text.length
    fun firstElement() = xs.first()
    fun countWithDefault() = count()
    fun countWithArgument() = count(offset = 2)
    fun usesSingleton() = identity() === Companion

    companion object {
        val xs = listOf(1)
        val text = "abc"
        fun getXs() = xs
        fun count(offset: Int = 0) = xs.size + offset
        fun identity() = this
    }
}

class Shadow {
    val value = 11
    fun choose() = 12
    fun propertyValue(): Int = value
    fun functionValue(): Int = choose()
    fun localValue(): Int {
        val value = 13
        return value
    }

    companion object {
        val value = "companion"
        fun choose() = "companion"
    }
}

interface Named {
    fun size() = xs.size + getXs().size + Factory.xs.size + Named.xs.size
    companion object Factory {
        val xs = listOf(1, 2)
        fun getXs() = xs
    }
}

class NamedImpl : Named

fun main() {
    val a = A()
    println(a.initialSize)
    println(a.initialCallSize)
    println(a.f())
    println(a.g())
    println(a.h())
    println(a.i())
    println(a.textLength())
    println(a.firstElement())
    println(a.countWithDefault())
    println(a.countWithArgument())
    println(a.usesSingleton())
    println(A.xs.size)
    println(A.text.length)
    val shadow = Shadow()
    println(shadow.propertyValue())
    println(shadow.functionValue())
    println(shadow.localValue())
    println(Shadow.value)
    println(Shadow.choose())
    println(NamedImpl().size())
}
