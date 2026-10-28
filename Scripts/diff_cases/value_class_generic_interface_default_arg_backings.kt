@JvmInline value class NumberValue(val value: Int)
@JvmInline value class DoubleValue(val value: Double)
@JvmInline value class MaybeValue(val value: String?)
class Payload(val text: String)
@JvmInline value class RefValue(val value: Payload)
@JvmInline value class GenericText<T : String>(val value: T)

interface NumberService<T> { fun number(value: T, suffix: String = "!"): String }
class NumberImpl : NumberService<NumberValue> {
    override fun number(value: NumberValue, suffix: String): String = value.value.toString() + suffix
}
interface DoubleService<T> { fun double(value: T, suffix: String = "!"): String }
class DoubleImpl : DoubleService<DoubleValue> {
    override fun double(value: DoubleValue, suffix: String): String = value.value.toString() + suffix
}
interface MaybeService<T> { fun maybe(value: T, suffix: String = "!"): String }
class MaybeImpl : MaybeService<MaybeValue> {
    override fun maybe(value: MaybeValue, suffix: String): String = (value.value ?: "null") + suffix
}
interface RefService<T> { fun reference(value: T, suffix: String = "!"): String }
class RefImpl : RefService<RefValue> {
    override fun reference(value: RefValue, suffix: String): String = value.value.text + suffix
}
interface StringService<T> { fun text(value: T, suffix: String = "!"): String }
class StringImpl : StringService<String> {
    override fun text(value: String, suffix: String): String = value + suffix
}
interface GenericService<T> { fun generic(value: T, suffix: String = "!"): String }
class GenericImpl : GenericService<GenericText<String>> {
    override fun generic(value: GenericText<String>, suffix: String): String = value.value + suffix
}
fun main() {
    val number: NumberService<NumberValue> = NumberImpl()
    println(NumberImpl().number(NumberValue(42)))
    println(number.number(NumberValue(42)))
    val double: DoubleService<DoubleValue> = DoubleImpl()
    println(DoubleImpl().double(DoubleValue(-0.0)))
    println(double.double(DoubleValue(-0.0)))
    val maybe: MaybeService<MaybeValue> = MaybeImpl()
    println(MaybeImpl().maybe(MaybeValue(null)))
    println(maybe.maybe(MaybeValue("X")))
    val reference: RefService<RefValue> = RefImpl()
    println(RefImpl().reference(RefValue(Payload("R"))))
    println(reference.reference(RefValue(Payload("R"))))
    val string: StringService<String> = StringImpl()
    println(StringImpl().text("S"))
    println(string.text("S"))
    val generic: GenericService<GenericText<String>> = GenericImpl()
    println(GenericImpl().generic(GenericText("G")))
    println(generic.generic(GenericText("G")))
}
