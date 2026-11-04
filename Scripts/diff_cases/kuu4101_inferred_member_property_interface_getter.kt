// KUU-4101: an inferred member property declared in a later class must
// publish its type before earlier bodies read it. `Wrap.size` derives from
// the intrinsic array member `IntArray.size`, and `Iface.isZero` lives on an
// interface — both used to stay `Any?`, degrading reads to the error type and
// masking them as `SEMA-0309` ("function invocation 'size()' expected").
interface Iface {
    val signum: Int
    val isZero get() = signum == 0
}

interface Ctor {
    fun create(v: Int): Iface
}

class Holder private constructor(
    val data: Wrap,
    override val signum: Int,
    var dummy: Boolean
) : Iface, Ctor by Holder {
    companion object : Ctor {
        operator fun invoke(data: Wrap, signum: Int): Holder = Holder(data, signum, false)
        override fun create(v: Int): Holder = Holder(Wrap(1), 1, false)
    }

    fun isZeroCheck(): Boolean = data.isZero
    fun resized(): Holder = Holder(
        Wrap(this.data.size).also {
            for (n in 0 until it.size) it[n] = this.data[n]
        },
        1,
    )
}

class Wrap internal constructor(val data: IntArray) : Iface {
    override val signum: Int get() = data.size
    val size get() = data.size
    constructor(size: Int) : this(IntArray(if (size > 1) size else 1))
    operator fun get(index: Int): Int = data[index]
    operator fun set(index: Int, value: Int) { data[index] = value }
}

fun main() {
    val h = Holder.create(3).resized()
    println(h.data.size)
    println(h.isZeroCheck())
    println(h.signum)
}
