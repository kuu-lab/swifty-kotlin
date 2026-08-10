#if canImport(Testing)
@testable import CompilerCore
import Testing

/// Tests for interface default methods (CLASS-003 / P5-113).
///
/// Verifies that interface functions with bodies (default methods) are:
/// 1. Parsed and preserved in the AST
/// 2. NOT marked abstract in the sema symbol table
/// 3. Callable on implementing classes that do not override them
/// 4. Correctly overridden when a concrete class provides its own implementation
/// 5. Lowered to KIR without errors
/// 6. Dispatched correctly through itable when receiver is interface-typed
@Suite struct InterfaceDefaultMethodTests {
    // MARK: - Sema: default methods are not abstract
    // MARK: - Consolidated Interface Default Method SemaClean tests
    @Test
    func testInterfaceDefaultMethodSemaClean() throws {
        let sources: [String] = [
            // testInterfaceDefaultMethodNotMarkedAbstract
            """
            package sample0

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }

            """,
            // testInterfaceAbstractMethodIsMarkedAbstract
            """
            package sample1

                    interface Greeter {
                        fun greet(): String
                    }

            """,
            // testConcreteClassInheritsDefaultMethodWithoutOverride
            """
            package sample2

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    class DefaultGreeter : Greeter

            """,
            // testConcreteClassOverridesDefaultMethod
            """
            package sample3

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    class CustomGreeter : Greeter {
                        override fun greet(): String = "Hi"
                    }

            """,
            // testInterfaceWithMixedAbstractAndDefaultMethods
            """
            package sample4

                    interface Animal {
                        fun name(): String
                        fun sound(): String = "..."
                    }
                    class Dog : Animal {
                        override fun name(): String = "Dog"
                    }

            """,
            // testClassImplementsMultipleInterfacesWithDefaults
            """
            package sample5

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    interface Logger {
                        fun log(): String = "logged"
                    }
                    class MyClass : Greeter, Logger

            """,
            // testDefaultMethodWithBlockBody
            """
            package sample6

                    interface Calculator {
                        fun add(a: Int, b: Int): Int {
                            return a + b
                        }
                    }
                    class SimpleCalc : Calculator

            """,
            // testDefaultMethodCallableOnImplementingClass
            """
            package sample7

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    class DefaultGreeter : Greeter
                    fun main() {
                        val g = DefaultGreeter()
                        println(g.greet())
                    }

            """,
            // testDefaultMethodCallableOnInterfaceTypedVariable
            """
            package sample8

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    class DefaultGreeter : Greeter
                    fun main() {
                        val g: Greeter = DefaultGreeter()
                        println(g.greet())
                    }

            """,
            // testInterfaceAbstractProperty
            """
            package sample9

                    interface TestInterface {
                        val abstractProperty: String
                        var abstractVar: Int
                    }
                    class TestClass : TestInterface {
                        override val abstractProperty: String = "test"
                        override var abstractVar: Int = 42
                    }

            """,
            // testInterfaceConcreteProperty
            """
            package sample10

                    interface TestInterface {
                        val concreteProperty: String
                            get() = "default"
                        var concreteVar: Int
                            get() = 42
                            set(value) {}
                    }
                    class TestClass : TestInterface

            """,
            // testInterfaceComputedProperty
            """
            package sample11

                    interface TestInterface {
                        val computedProperty: String
                            get() = "computed"
                        var computedVar: String
                            get() = "get"
                            set(value) { }
                    }
                    class TestClass : TestInterface

            """,
            // testSuperQualifiedCall
            """
            package sample12

                    interface A {
                        fun method(): String = "A"
                    }
                    interface B : A {
                        override fun method(): String = "B"
                    }
                    interface C : A {
                        override fun method(): String = "C"
                    }
                    class TestClass : B, C {
                        override fun method(): String = super<B>.method() + " + " + super<C>.method()
                    }

            """,
            // testDiamondConflictResolutionUsesFullSignature
            """
            package sample13

                    interface Left {
                        fun method(value: Int): String = "LeftInt"
                    }
                    interface Right {
                        fun method(value: String): String = "RightString"
                    }
                    class TestClass : Left, Right

            """,
            // testConcreteSuperclassDefaultBeatsInterfaceConflict
            """
            package sample14

                    open class Base {
                        open fun method(): String = "Base"
                    }
                    interface Left {
                        fun method(): String = "Left"
                    }
                    interface Right {
                        fun method(): String = "Right"
                    }
                    class TestClass : Base(), Left, Right

            """,
            // testConcreteSuperclassDefaultCallResolvesWithoutAmbiguity
            """
            package sample15

                    open class Base {
                        open fun method(): String = "Base"
                    }
                    interface Left {
                        fun method(): String = "Left"
                    }
                    interface Right {
                        fun method(): String = "Right"
                    }
                    class TestClass : Base(), Left, Right
                    fun main() {
                        println(TestClass().method())
                    }

            """,
            // testSignatureAwareInheritedOverloadsResolveCalls
            """
            package sample16

                    interface Left {
                        fun method(value: Int): String = "LeftInt"
                    }
                    interface Right {
                        fun method(value: String): String = "RightString"
                    }
                    class TestClass : Left, Right
                    fun main() {
                        val instance = TestClass()
                        println(instance.method(1))
                        println(instance.method("x"))
                    }

            """,
            // testComplexInterfaceInheritance
            """
            package sample17

                    interface Base {
                        fun baseMethod(): String = "Base"
                        abstract fun abstractMethod(): String
                    }
                    interface Left : Base {
                        override fun baseMethod(): String = "Left"
                        fun leftMethod(): String = "Left"
                    }
                    interface Right : Base {
                        // Don't override baseMethod to avoid diamond conflict
                        fun rightMethod(): String = "Right"
                    }
                    class TestClass : Left, Right {
                        override fun abstractMethod(): String = "Implemented"
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = (sema, interner)

            // testInterfaceDefaultMethodNotMarkedAbstract
            do {
                let samplePackage = "sample0"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))

                // The greet function should NOT have the abstractType flag
                let greetSymbols = sema.symbols.allSymbols().filter { $0.kind == .function && interner.resolve($0.name) == "greet" && interner.resolve($0.fqName[0]) == samplePackage }
                #expect(greetSymbols.count == 1)
                #expect(!(greetSymbols[0].flags.contains(.abstractType)),
                               "Interface default method should not be marked abstract")
            }

            // testInterfaceAbstractMethodIsMarkedAbstract
            do {
                let samplePackage = "sample1"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))

                let greetSymbols = sema.symbols.allSymbols().filter { $0.kind == .function && interner.resolve($0.name) == "greet" && interner.resolve($0.fqName[0]) == samplePackage }
                #expect(greetSymbols.count == 1)
                #expect(greetSymbols[0].flags.contains(.abstractType),
                              "Interface method without body should be marked abstract")
            }

            // testConcreteClassInheritsDefaultMethodWithoutOverride
            do {
                let samplePackage = "sample2"
                _ = samplePackage


                // No abstract override error: default method satisfies the requirement
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testConcreteClassOverridesDefaultMethod
            do {
                let samplePackage = "sample3"
                _ = samplePackage


                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testInterfaceWithMixedAbstractAndDefaultMethods
            do {
                let samplePackage = "sample4"
                _ = samplePackage


                // Dog overrides name() (abstract) and inherits sound() (default)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testClassImplementsMultipleInterfacesWithDefaults
            do {
                let samplePackage = "sample5"
                _ = samplePackage


                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testDefaultMethodWithBlockBody
            do {
                let samplePackage = "sample6"
                _ = samplePackage


                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testDefaultMethodCallableOnImplementingClass
            do {
                let samplePackage = "sample7"
                _ = samplePackage


                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty,
                              "Calling inherited default method should not produce errors. Got: \(errors.map(\.message))")
            }

            // testDefaultMethodCallableOnInterfaceTypedVariable
            do {
                let samplePackage = "sample8"
                _ = samplePackage


                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty,
                              "Calling default method on interface-typed var should not error. Got: \(errors.map(\.message))")
            }

            // testInterfaceAbstractProperty
            do {
                let samplePackage = "sample9"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testInterfaceConcreteProperty
            do {
                let samplePackage = "sample10"
                _ = samplePackage

                // Real kotlinc rejects property initializers in interfaces
                // ("property initializers in interfaces are prohibited"), so default
                // property values must be expressed via a getter (and a no-op setter
                // for `var`), not `= expr`.

                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testInterfaceComputedProperty
            do {
                let samplePackage = "sample11"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testSuperQualifiedCall
            do {
                let samplePackage = "sample12"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testDiamondConflictResolutionUsesFullSignature
            do {
                let samplePackage = "sample13"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0171" })))
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testConcreteSuperclassDefaultBeatsInterfaceConflict
            do {
                let samplePackage = "sample14"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0171" })))
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testConcreteSuperclassDefaultCallResolvesWithoutAmbiguity
            do {
                let samplePackage = "sample15"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0003" })))
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testSignatureAwareInheritedOverloadsResolveCalls
            do {
                let samplePackage = "sample16"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0003" })))
                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }

            // testComplexInterfaceInheritance
            do {
                let samplePackage = "sample17"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
            }
        }
    }
    // MARK: - Consolidated Interface Default Method SemaErrors tests
    @Test
    func testInterfaceDefaultMethodSemaErrors() throws {
        let sources: [String] = [
            // testConcreteClassMustOverrideAbstractInterfaceMethod
            """
            package sample0

                    interface Greeter {
                        fun greet(): String
                    }
                    class DefaultGreeter : Greeter

            """,
            // testMixedMethodsMissingAbstractOverrideErrors
            """
            package sample1

                    interface Animal {
                        fun name(): String
                        fun sound(): String = "..."
                    }
                    class Dog : Animal

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = (sema, interner)

            // testConcreteClassMustOverrideAbstractInterfaceMethod
            do {
                let samplePackage = "sample0"
                _ = samplePackage


                // Abstract method without body must be overridden
                assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
            }

            // testMixedMethodsMissingAbstractOverrideErrors
            do {
                let samplePackage = "sample1"
                _ = samplePackage


                // Dog must override the abstract name() even though sound() has a default
                assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
            }
        }
    }
    // MARK: - Consolidated Interface Default Method Lowering tests
    @Test
    func testInterfaceDefaultMethodLowering() throws {
        let sources: [String] = [
            // testInterfaceDefaultMethodKIREmission
            """
            package sample0

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    class DefaultGreeter : Greeter
                    fun main() {
                        println(DefaultGreeter().greet())
                    }

            """,
            // testOverriddenDefaultMethodKIREmission
            """
            package sample1

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    class CustomGreeter : Greeter {
                        override fun greet(): String = "Hi"
                    }
                    fun main() {
                        println(CustomGreeter().greet())
                    }

            """,
            // testDefaultMethodFullPipelineLowering
            """
            package sample2

                    interface Greeter {
                        fun greet(): String = "Hello"
                    }
                    class DefaultGreeter : Greeter
                    class CustomGreeter : Greeter {
                        override fun greet(): String = "Hi"
                    }
                    fun main() {
                        println(DefaultGreeter().greet())
                        println(CustomGreeter().greet())
                    }

            """,
            // testMixedMethodsFullPipelineLowering
            """
            package sample3

                    interface Animal {
                        fun name(): String
                        fun sound(): String = "..."
                    }
                    class Dog : Animal {
                        override fun name(): String = "Dog"
                    }
                    fun main() {
                        val d = Dog()
                        println(d.name())
                        println(d.sound())
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToLowering(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            _ = (sema, interner)

            // testInterfaceDefaultMethodKIREmission
            do {
                let samplePackage = "sample0"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                               "KIR lowering should succeed. Got: \(ctx.diagnostics.diagnostics.map(\.message))")
                let module = try #require(ctx.kir)
                #expect(module.functionCount >= 1)
            }

            // testOverriddenDefaultMethodKIREmission
            do {
                let samplePackage = "sample1"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                               "KIR lowering with override should succeed. Got: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testDefaultMethodFullPipelineLowering
            do {
                let samplePackage = "sample2"
                _ = samplePackage


                #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })),
                               "Full pipeline lowering should succeed. Got: \(ctx.diagnostics.diagnostics.map(\.message))")
            }

            // testMixedMethodsFullPipelineLowering
            do {
                let samplePackage = "sample3"
                _ = samplePackage


                let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
                #expect(errors.isEmpty,
                              "Mixed abstract+default pipeline should succeed. Got: \(errors.map(\.message))")
            }
        }
    }
}
#endif
