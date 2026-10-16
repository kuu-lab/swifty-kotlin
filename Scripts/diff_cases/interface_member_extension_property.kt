interface ExtensionPropertyContract {
    val Int.a: String
    fun Int.foo(): String
}

class ExtensionPropertyImplementation : ExtensionPropertyContract {
    override val Int.a: String get() = "interface property"
    override fun Int.foo(): String = "interface function"
    val ordinary: String = "member property"
}

val Int.packageProperty: String get() = "package extension property"

class LocalExtensionProperty {
    val Int.local: String get() = "class member extension property"
    fun read(): String = 1.local
}

fun box(): String = with(ExtensionPropertyImplementation()) {
    if (1.foo() == "interface function"
        && 1.a == "interface property"
        && 1.packageProperty == "package extension property"
        && ordinary == "member property"
        && LocalExtensionProperty().read() == "class member extension property"
    ) {
        "OK"
    } else {
        "FAIL"
    }
}

fun main() { println(box()) }
