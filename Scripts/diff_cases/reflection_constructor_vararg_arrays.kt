annotation class Label(vararg val names: String)
class TextBundle(vararg values: String) { val count: Int = values.size }
class IntBundle(vararg values: Int) { val count: Int = values.size; val total: Int = values[0] + values[1] }
class DoubleBundle(vararg values: Double) { val count: Int = values.size; val total: Double = values[0] + values[1] }
fun main() {
    println(Label("a", "b").names.size)
    println(TextBundle("a", "b").count)
    val labelCtor = Label::class.constructors.single()
    println(labelCtor.parameters.single().type)
    println(labelCtor.parameters.single().isVararg)
    println((labelCtor.call(arrayOf("a", "b")) as Label).names.size)
    val textCtor = TextBundle::class.constructors.single()
    println((textCtor.call(arrayOf("a", "b")) as TextBundle).count)
    val intCtor = IntBundle::class.constructors.single()
    println(intCtor.parameters.single().type)
    val ints = intCtor.call(intArrayOf(2, 3)) as IntBundle
    println(ints.count)
    println(ints.total)
    val doubleCtor = DoubleBundle::class.constructors.single()
    println(doubleCtor.parameters.single().type)
    val doubles = doubleCtor.call(doubleArrayOf(1.25, 2.75)) as DoubleBundle
    println(doubles.count)
    println(doubles.total)
}
