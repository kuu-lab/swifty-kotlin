// KSP-944: source-backed MutableList shell and initializer factory.
abstract class CustomMutableList : MutableList<String>

fun mutableListProbe(values: MutableList<Int>): List<Number> = values

fun mutableListFactoryProbe(): MutableList<Int> = MutableList(3) { it }

fun mutableListTypeProbe(value: Any): Boolean = value is MutableList<*>
