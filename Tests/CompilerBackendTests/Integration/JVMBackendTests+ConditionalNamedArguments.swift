#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test
    func conditionalNamedArgumentsLeaveFollowingArgumentsForTheCall() throws {
        try withWorkspace { root in
            try runM4("""
            private const val Small = 2601
            private const val Medium = 2602

            class Shape(val seed: Int, val size: Int)

            fun sample(medium: Boolean): Int {
                var padding = 0
                if (medium) padding = 1 else padding = 2
                val shape = Shape(
                    seed = if (medium) Medium else Small,
                    size = if (medium) 322 else 142,
                )
                return shape.seed + shape.size + padding
            }

            fun main() {
                println(sample(false))
                println(sample(true))
            }
            """, expected: "2745\n2925\n", mode: .jvmJar, root: root)
        }
    }
}
#endif
