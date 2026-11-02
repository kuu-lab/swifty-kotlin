@testable import CompilerCore
import Testing

@Suite
struct KUU4091PropertyAccessorParametersTests {
    @Test
    func propertyAccessorParametersHaveAccessorIdentityAndDescriptions() throws {
        try compileAndRunKotlin(
            """
            class C(val v: Int) { var w: Int = 0 }

            fun main() {
                val getter = C::v.getter
                val getterParameter = getter.parameters[0]
                println(getterParameter == C::v.parameters[0])
                println(getterParameter == C::v.getter.parameters[0])
                println(getterParameter.hashCode() == C::v.getter.parameters[0].hashCode())
                println(getterParameter)

                val setter = C::w.setter
                val setterReceiver = setter.parameters[0]
                println(setterReceiver == C::w.parameters[0])
                println(setterReceiver == C::w.setter.parameters[0])
                println(setterReceiver)
                println(setter.parameters[1])
                println(setter.parameters[1] == C::w.setter.parameters[1])

                println(getter.callBy(mapOf(getter.parameters[0] to C(6))))
                val target = C(0)
                setter.callBy(mapOf(setter.parameters[0] to target, setter.parameters[1] to 9))
                println(target.w)
            }
            """,
            expectedOutput: "false\ntrue\ntrue\ninstance parameter of fun C.`<get-v>`(): kotlin.Int\n"
                + "false\ntrue\ninstance parameter of fun C.`<set-w>`(kotlin.Int): kotlin.Unit\n"
                + "parameter #1 null of fun C.`<set-w>`(kotlin.Int): kotlin.Unit\n"
                + "true\n6\n9\n",
            moduleName: "KUU4091PropertyAccessorParameters"
        )
    }
}
