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
            fun make(): Holder { observed += 1; return Holder }
            class Holder {
                companion object {
                    @JvmStatic fun twice(x: Int): Int = x * 2
                    @JvmStatic fun greet(name: String = "world"): String = "hi " + name
                }
            }
            fun main() {
                println(Holder.twice(5))
                println(make().twice(3))
                println(Holder.greet())
                println(Holder.greet("sushi"))
                println(observed)
            }
            """, expected: "10\n6\nhi world\nhi sushi\n1\n", mode: mode, root: root)
        }
    }
}
#endif
