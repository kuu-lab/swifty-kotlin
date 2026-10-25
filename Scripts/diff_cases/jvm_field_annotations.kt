class FieldFlags {
    @Volatile var implicitVolatile = 1
    @Transient var implicitTransient = 2
    @field:kotlin.jvm.Volatile var explicitVolatile = 3
    @field:kotlin.jvm.Transient var explicitTransient = 4
}

fun main() {
    val flags = FieldFlags()
    flags.implicitVolatile = 5
    flags.explicitTransient = 6
    println(flags.implicitVolatile)
    println(flags.implicitTransient)
    println(flags.explicitVolatile)
    println(flags.explicitTransient)
}
