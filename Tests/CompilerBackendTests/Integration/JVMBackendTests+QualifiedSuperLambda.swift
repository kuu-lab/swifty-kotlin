#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func labeledSuperCallInsideLambdaInvokesSuperclass(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM11("""
            open class Base {
                open fun compute(value: Int): Int = value + 1
            }
            class Derived : Base() {
                override fun compute(value: Int): Int = transaction { super@Derived.compute(value) }
                fun transaction(block: () -> Int): Int = block()
            }
            fun main() {
                println(Derived().compute(41))
            }
            """, expected: "42\n", mode: mode, root: root)
        }
    }

    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func labeledSuperCallInsideSuspendLambdaInvokesSuperclass(mode: EmitMode) throws {
        try withWorkspace { root in
            try runM7Coroutine("""
            interface Dao {
                suspend fun upsert(value: Int): Int = value + 1
            }
            class Impl : Dao {
                override suspend fun upsert(value: Int): Int = transaction { super@Impl.upsert(value) }
                suspend fun transaction(block: suspend () -> Int): Int = block()
            }
            suspend fun main() {
                println(Impl().upsert(41))
            }
            """, expected: "42\n", mode: mode, root: root)
        }
    }

    @Test
    func unresolvedQualifiedSuperLabelIsRejected() throws {
        try withWorkspace { root in
            let result = try compile("""
            open class Base {
                open fun compute(value: Int): Int = value
            }
            class Derived : Base() {
                override fun compute(value: Int): Int = transaction { super@Missing.compute(value) }
                fun transaction(block: () -> Int): Int = block()
            }
            fun main() {}
            """, root: root, mode: .jvmJar)
            #expect(result.0 != 0)
            #expect(result.1.contains { $0.code == "KSWIFTK-SEMA-0053" })
            #expect(!result.1.contains { $0.code == "KSWIFTK-JVM-0001" })
        }
    }
}
#endif
