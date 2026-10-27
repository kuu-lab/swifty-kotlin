#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendInnerClassOuterReceiverExecutionTests {
    @Test func inheritedLateinitIsInitializedUsesInnerReceiver() throws {
        let source = """
            open class Foo {
                lateinit var bar: String
                inner class InnerSubclass : Foo() {
                    fun isBarInitialized(): Boolean = this::bar.isInitialized
                }
            }
            fun main() {
                val inner = Foo().InnerSubclass()
                if (inner.isBarInitialized()) {
                    val unexpected = inner.bar
                } else {
                    inner.bar = "initialized"
                    val expected = inner.bar
                }
            }
            """
        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "InheritedLateinitInInnerClass",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                includeStdlib: false,
                allowDefaultStdlibLibrary: false
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0)
        }
    }

    /// KUU-2846: a nested inner subclass and a local subclass of an inner
    /// class declared in an outer scope must capture the current `Child`
    /// instance. It is a `Father` subtype with its own constructor state.
    @Test func innerSupertypeFromOuterScopeCapturesCurrentReceiver() throws {
        try assertKotlinOutput(
            """
            open class Father(val param: String) {
                abstract inner class InClass {
                    fun work(): String = param
                }

                inner class Child(p: String) : Father(p) {
                    inner class Child2 : Father.InClass()

                    inner class Child2ViaSecondary : Father.InClass {
                        constructor() : super()
                    }

                    fun localExtendsInner(): InClass {
                        class Local : Father.InClass()
                        return Local()
                    }
                }
            }

            fun main() {
                val child = Father("fail").Child("OK")
                println(child.Child2().work())
                println(child.Child2ViaSecondary().work())
                println(child.localExtendsInner().work())
            }
            """,
            moduleName: "KUU2846InnerExtendsOuterInner",
            expected: "OK\nOK\nOK\n"
        )
    }

    @Test func unqualifiedOuterMemberCallUsesCapturedOuterInstance() throws {
        try assertKotlinOutput(
            """
            class Outer(val value: Int) {
                fun fetch(index: Int): Int = value + index
                inner class Inner {
                    fun compute(): Int = fetch(1)
                }
            }
            fun main() = println(Outer(7).Inner().compute())
            """,
            moduleName: "InnerClassOuterReceiverCall",
            expected: "8\n"
        )
    }

    @Test
    func qualifiedThisSelectsEnclosingInstanceWhenInnerClassExtendsOuterClass() throws {
        try assertKotlinOutput(
            """
            open class Outer private constructor(val s: String) {
                inner class Inner : Outer("O") {
                    fun foo() = this.s + this@Outer.s
                }
                class Nested : Outer("K")
                fun bar() = Inner()
            }
            fun main() { println(Outer.Nested().bar().foo()) }
            """,
            moduleName: "QualifiedThisWhenInnerExtendsOuter",
            expected: "OK\n"
        )
    }

    @Test func unqualifiedOuterMemberCallFromAnonymousObjectUsesCapturedOuterInstance() throws {
        try assertKotlinOutput(
            """
            interface Getter<E> {
                fun fetch(index: Int): E
            }
            class ConstGetter(val value: Int) : Getter<Int> {
                override fun fetch(index: Int): Int = value + index
                fun call(): Int {
                    val result = object : Any() {
                        fun compute(): Int = fetch(3)
                    }
                    return result.compute()
                }
            }
            fun main() = println(ConstGetter(7).call())
            """,
            moduleName: "AnonymousObjectOuterReceiverCall",
            expected: "10\n"
        )
    }

    @Test func innerClassInsideAnonymousObjectCapturesOuterReceiver() throws {
        try assertKotlinOutput(
            """
            class A(val x: String) {
                fun value(): String {
                    return object {
                        inner class Y {
                            val y = x
                        }
                        fun value() = Y().y
                    }.value()
                }
            }
            fun main() { println(A("OK").value()) }
            """,
            moduleName: "InnerClassInsideAnonymousObjectOuterCapture",
            expected: "OK\n"
        )
    }

    @Test func deeplyNestedInnerClassesInsideAnonymousObjectsCaptureGenericOuter() throws {
        try assertKotlinOutput(
            """
            class Generic<T>(val t: T) {
                fun foo(): T {
                    val o1 = object {
                        inner class InnerLocal1 {
                            fun bar(): T {
                                val o2 = object {
                                    inner class InnerLocal2 {
                                        fun baz(): T = t
                                    }
                                }
                                return o2.InnerLocal2().baz()
                            }
                        }
                    }
                    return o1.InnerLocal1().bar()
                }
            }
            fun main() { println(Generic("OK").foo()) }
            """,
            moduleName: "KUU3556NestedInnerClassGenericCapture",
            expected: "OK\n"
        )
    }

    @Test
    func localOwnerInnerConstructorCapturesEnclosingInstances() throws {
        try assertKotlinOutput(
            """
            class Host {
                val a = 1
                fun calculate(): Int {
                    class Owner {
                        val b = 2
                        inner class Child {
                            val c = 3
                            fun value() = this@Host.a + this@Owner.b + this.c
                        }
                    }
                    return Owner().Child().value()
                }
            }
            fun String.bar(): String {
                open class Local { fun result() = this@bar }
                class ExtensionOwner {
                    inner class Inner : Local() {
                        fun owner() = this@ExtensionOwner
                    }
                }
                return ExtensionOwner().Inner().result()
            }
            fun main() {
                println(Host().calculate())
                println("OK".bar())
            }
            """,
            moduleName: "LocalOwnerInnerConstructor",
            expected: "6\nOK\n"
        )
    }
}
#endif
