// KUU-1753: reflected annotations must be instances of the declared class.
annotation class Named(val value: String)
@Named("wire.Record") class Tagged
fun main() {
    val tags = Tagged::class.annotations
    println(tags.size)
    println(tags[0].annotationClass.simpleName)
    println(tags[0] is Named)
    println(tags.filterIsInstance<Named>().size)
}
