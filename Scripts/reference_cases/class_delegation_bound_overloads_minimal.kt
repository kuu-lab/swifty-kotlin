interface Bounded {
    fun <T : CharSequence> echo(value: T): T
    fun <T : Number> echo(value: T): T
}
class BoundedImpl : Bounded {
    override fun <T : CharSequence> echo(value: T): T = value
    override fun <T : Number> echo(value: T): T = value
}
class BoundedDelegate(base: Bounded) : Bounded by base
fun main() {
    val concrete = BoundedDelegate(BoundedImpl())
    val control: Bounded = concrete
    val text: String = concrete.echo("text")
    val number: Int = concrete.echo(7)
    val controlText: String = control.echo("control")
    val controlNumber: Int = control.echo(9)
}
