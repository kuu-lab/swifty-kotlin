class Test {
    private fun <T : Any> T.self() = object {
        fun calc(): T = this@self
    }

    fun extensionValue(): Int = 1.self().calc() + 1
}

private class Factory {
    private fun <T : Any> makeMember(value: T) = object {
        fun calc(): T = value
    }

    fun memberValue(): Int = makeMember(2).calc()
}

private fun <T : Any> makeTopLevel(value: T) = object {
    fun calc(): T = value
}

private fun fixedObject() = object {
    fun calc(): Int = 1
}

private fun <T : Any> T.identity(): T = this

class Holder<T>(val value: T) {
    fun get(): T = value
}

fun box(): String {
    val extension: Int = Test().extensionValue()
    val member: Int = Factory().memberValue()
    val topLevel: Int = makeTopLevel(3).calc()
    val fixed: Int = fixedObject().calc()
    val directExtension: Int = 1.identity()
    val namedGeneric: Int = Holder(4).get()
    return if (extension + member + topLevel + fixed + directExtension + namedGeneric == 13) "OK" else "FAIL"
}

fun main() {
    println(box())
}
