#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func implicitMemberExtensionCallUsesTheLambdaReceiver(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11(#"""
            class Owner {
                fun String.ext(): Int = length
                fun inlineReceiver(): Int = with("abc") { ext() }
                fun closureReceiver(): Int {
                    val measure: String.() -> Int = { ext() }
                    return "abcdefg".measure()
                }
            }
            fun main() {
                println(Owner().inlineReceiver())
                println(Owner().closureReceiver())
            }
            """#, expected: "3\n7\n", mode: mode, root: root)
        }
    }
}
#endif
