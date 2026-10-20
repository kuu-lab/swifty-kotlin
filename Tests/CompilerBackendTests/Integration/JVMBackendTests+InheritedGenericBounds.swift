#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func inheritedMethodGenericBoundBridges(mode: EmitMode) throws {
        try assertJVM("""
        interface Echo<A> { fun <T : A> echo(value: T): T }
        open class Base<B> { open fun <T : B> echo(value: T): T = value }
        class Implementation : Base<Number>(), Echo<Number>
        class Forward(base: Echo<Number>) : Echo<Number> by base
        class Explicit : Base<Number>(), Echo<Number> {
            override fun <T : Number> echo(value: T): T = value
        }
        interface Mapper<T> { fun map(value: T): String }
        class IntMapper : Mapper<Int> { override fun map(value: Int): String = "int:" + value }
        interface Covariant { fun value(index: Int): Any }
        class Narrow : Covariant { override fun value(index: Int): String = "narrow:" + index }
        fun main() {
            val direct = Implementation()
            println(direct.echo(7))
            val inherited: Echo<Number> = direct
            println(inherited.echo(9))
            val forwarded: Echo<Number> = Forward(direct)
            println(forwarded.echo(11))
            val explicit: Echo<Number> = Explicit()
            println(explicit.echo(13))
            val mapper: Mapper<Int> = IntMapper()
            println(mapper.map(17))
            val covariant: Covariant = Narrow()
            println(covariant.value(19))
        }
        """, "7\n9\n11\n13\nint:17\nnarrow:19\n", mode: mode)
    }
}
#endif
