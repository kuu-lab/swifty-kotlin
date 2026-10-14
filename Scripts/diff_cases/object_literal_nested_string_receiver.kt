interface Reader { fun read(): Int }

fun String.codes(): Sequence<Int> = object : Sequence<Int> {
    override fun iterator(): Iterator<Int> = object : Iterator<Int> {
        private var index = 0
        override fun hasNext(): Boolean = index < 2
        override fun next(): Int = get(index++).code
    }
}

fun String.firstCode(): Int = get(0).code
fun String.extensionReader(): Reader = object : Reader {
    override fun read(): Int = firstCode()
}
fun String.explicitReader(): Reader = object : Reader {
    override fun read(): Int = this@explicitReader.get(0).code
}
fun String.decoratedReader(extra: Int): Reader {
    val suffix = extra
    return object : Reader {
        private fun bias(): Int = suffix
        override fun read(): Int = get(0).code + bias()
    }
}
fun String.ownReader(): Reader = object : Reader {
    fun get(index: Int): Char = 'Z'
    override fun read(): Int = get(0).code
}
fun String.nearerReader(): Reader = with("K") {
    object : Reader {
        override fun read(): Int = get(0).code
    }
}
fun String.nullableShadowReader(): Reader = with(null as String?) {
    object : Reader {
        override fun read(): Int = firstCode()
    }
}
fun <T> T.receiverCode(): Int = if (this == null) 1 else 2
fun String.nullableGenericCode(): Int = with(null as String?) { receiverCode() }

fun main() {
    val a = "AB".codes().iterator()
    val b = "CD".codes().iterator()
    println(a.hasNext())
    println(a.next())
    println(b.next())
    println(a.next())
    println(b.next())
    println(a.hasNext())
    println("E".extensionReader().read())
    println("F".explicitReader().read())
    println("G".decoratedReader(3).read())
    println("H".firstCode())
    println("I".ownReader().read())
    println("J".nearerReader().read())
    println("L".nullableShadowReader().read())
    println("M".nullableGenericCode())
}
