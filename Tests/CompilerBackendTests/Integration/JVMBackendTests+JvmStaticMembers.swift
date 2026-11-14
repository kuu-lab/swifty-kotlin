#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func jvmStaticCompanionCallsPreserveDefaultsAndReceiverEffects(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM4("""
            var observed = 0
            class Holder {
                companion object {
                    @JvmStatic fun twice(x: Int): Int = x * 2
                    @JvmStatic fun greet(name: String = "world"): String = "hi " + name
                }
            }
            object Counter {
                var calls = 0
                @JvmStatic fun bump(x: Int): Int { calls += 1; return x + 1 }
            }
            fun fetch(): Counter { observed += 1; return Counter }
            fun main() {
                println(Holder.Companion.twice(5))
                println(Holder.Companion.greet())
                println(Holder.Companion.greet("sushi"))
                println(fetch().bump(4))
                println(observed)
                println(Counter.calls)
            }
            """, expected: "10\nhi world\nhi sushi\n5\n1\n1\n", mode: mode, root: root)
        }
    }
}
#endif
