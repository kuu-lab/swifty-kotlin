#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func takeUnlessFiltersReceiverLikeUpstream(mode: EmitMode) throws {
        let source = """
        class Box(val value: Int) {
            fun passed(): Boolean = value > 0
        }

        fun main() {
            val dropped = "hello".takeUnless { it.length > 3 }
            val kept = "hi".takeUnless { it.length > 3 }
            println(dropped)
            println(kept)
            val nullable: String? = null
            println(nullable?.takeUnless { it.isEmpty() })
            val box = Box(1)
            println(box.takeUnless { it.passed() } == null)
            println(Box(-1).takeUnless { it.passed() }?.value)
            // callsInPlace(EXACTLY_ONCE) contracts make predicate-side
            // initialization visible for lambda-literal predicates, as in
            // stock kotlinc; opaque function values stay rejected.
            var x: Int
            "hi".takeUnless { x = 5; false }
            println(x)
            var y: Int
            "yo".takeIf { y = 7; true }
            println(y)
        }
        """
        try withWorkspace { root in
            let result = try compile(source, root: root, mode: mode)
            try #require(result.0 == 0, "\(result.1.map(\.message))")
            let artifact = root.appendingPathComponent(mode == .jvmJar ? "hello.jar" : "classes").path
            let execution = try java(["-cp", artifact, "HelloKt"])
            #expect(execution.stdout == "null\nhi\nnull\ntrue\n-1\n5\n7\n")
            #expect(execution.stderr.isEmpty)
        }
    }
}
#endif
