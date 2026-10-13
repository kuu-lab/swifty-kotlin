fun main() {
    val concrete = BoundedDelegate(BoundedImpl())
    val control: Bounded = concrete
    val text: String = concrete.echo("text")
    val number: Int = concrete.echo(7)
    val controlText: String = control.echo("control")
    val controlNumber: Int = control.echo(9)
    println(text)
    println(number)
    println(controlText)
    println(controlNumber)
    val explicit = ExplicitBoundedDelegate(BoundedImpl())
    val explicitControl: Bounded = explicit
    println(explicit.echo("explicit"))
    println(explicit.echo(11))
    println(explicitControl.echo("interface"))
    println(explicitControl.echo(13))
    val inherited: BoundedBase = BoundedChild()
    println(inherited.echo("inherited"))
    println(inherited.echo(17))
    val generic = GenericDelegate<Marker>(GenericImpl())
    generic.choose(Marked())
    val genericControl: Generic<Marker> = generic
    genericControl.choose(Marked())
    val specialized = SpecializedDelegate(GenericImpl())
    specialized.choose(Marked())
    val specializedControl: Generic<Marker> = specialized
    specializedControl.choose(Marked())
    val reordered = ReorderedDelegate(MultipleImpl())
    reordered.choose(Both())
    val reorderedControl: Multiple = reordered
    reorderedControl.choose(Both())
    val any = ExplicitAnyDelegate(UnboundedImpl())
    println(any.choose(null))
    val anyControl: Unbounded = any
    println(anyControl.choose(null))
}
