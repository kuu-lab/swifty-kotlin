interface Deep { val label: String get() = "OK" }
class Leaf : Deep { fun read(): String = super.label }
fun probe(): String = Leaf().read()
