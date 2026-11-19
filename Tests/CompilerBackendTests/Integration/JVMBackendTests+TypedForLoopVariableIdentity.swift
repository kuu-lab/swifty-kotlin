#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    /// A for-loop variable with an explicitly declared reference supertype over
    /// primitive elements (`for (x: Any in doubleArrayOf(...))`) must keep the
    /// boxed value in the loop local: boxing it on every read would make
    /// `x === x` false, unlike kotlinc.
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func typedForLoopVariableKeepsBoxedIdentity(mode: EmitMode) throws {
        let source = """
        fun main() {
            for (x: Any in doubleArrayOf(1.0, 2.0)) {
                println(x === x)
                println(x !== x)
            }
            for (n: Number in intArrayOf(1, 2)) {
                println(n === n)
            }
            for (y in longArrayOf(3L)) {
                println(y === y)
            }
        }
        """
        let expected = """
        true
        false
        true
        false
        true
        true
        true

        """

        try withWorkspace { root in
            try runM11(source, expected: expected, mode: mode, root: root)
        }
    }
}
#endif
