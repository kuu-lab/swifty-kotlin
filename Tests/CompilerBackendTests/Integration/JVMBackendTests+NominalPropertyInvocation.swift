#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func nominalPropertyInvocationsReadGetterBeforeArguments(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            interface I
            operator fun I.invoke(): String = "extension"
            class C : I
            object H { val value = C() }
            interface F { operator fun invoke(): String }
            abstract class Base(val fn: F)
            object Test : Base(object : F {
                override fun invoke(): String = Test.ok()
            }) { fun ok(): String = "member" }
            var trace = ""
            open class Action {
                open operator fun invoke(value: Int = 3): Int { trace += "i"; return value + 10 }
            }
            class Derived : Action() {
                override operator fun invoke(value: Int): Int { trace += "v"; return value + 20 }
            }
            class Owner {
                val action: Action get() { trace += "g"; return Derived() }
            }
            class Box<T>(val action: T)
            fun owner(): Owner { trace += "r"; return Owner() }
            fun argument(): Int { trace += "a"; return 2 }
            fun main() {
                println(H.value()); println(H.value.invoke()); println(H?.value())
                println(Test.fn()); println(Test.fn.invoke())
                println(owner().action(argument())); println(trace)
                trace = ""
                println(owner().action()); println(trace)
                trace = ""
                val absent: Owner? = null
                println(absent?.action(argument())); println(trace)
                val present: Owner? = Owner()
                println(present?.action(value = argument())); println(trace)
                println(Box(Derived()).action(4))
            }
            """, expected: "extension\nextension\nextension\nmember\nmember\n22\nrgav\n23\nrgv\nnull\n\n22\ngav\n24\n", mode: mode, root: root)
        }
    }
}
#endif
