fun rejected(base: Bounded) {
    val concrete = BoundedDelegate(base)
    concrete.echo(true)
    base.echo(true)
}
