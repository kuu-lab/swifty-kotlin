#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite struct AbstractClassErrorTests {

    @Test(arguments: ["class", "open class", "final class", "object"])
    func testAbstractMembersInConcreteOwnerAreRejected(owner: String) throws {
        let ctx = makeContextFromSource("""
        \(owner) C {
            abstract fun f(): Int
            abstract val value: Int
            abstract var mutable: Int
        }
        """)
        try runSema(ctx)

        for name in ["f", "value", "mutable"] {
            #expect(ctx.diagnostics.diagnostics.contains {
                $0.code == "KSWIFTK-SEMA-MODIFIER-CONFLICT"
                    && $0.severity == .error
                    && $0.message.contains("'\(name)' in non-abstract class 'C'")
            })
        }
    }

    @Test func testConcreteAbstractFunctionCallIsRejected() throws {
        let ctx = makeContextFromSource("""
        class C {
            abstract fun f(): Int
            fun g(): Int = f()
        }
        fun main() {
            println(C().f())
            println(C().g())
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-MODIFIER-CONFLICT"
                && $0.severity == .error
                && $0.message.contains("'f' in non-abstract class 'C'")
        })
    }

    @Test func testNestedConcreteClassCannotUseOuterAbstractness() throws {
        let ctx = makeContextFromSource("""
        abstract class Outer {
            class C {
                abstract fun f(): Int
            }
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-MODIFIER-CONFLICT"
                && $0.severity == .error
                && $0.message.contains("non-abstract class 'C'")
        })
    }

    @Test(arguments: ["abstract class", "sealed class", "interface"])
    func testAbstractMembersInAbstractOwnerRemainValid(owner: String) throws {
        let ctx = makeContextFromSource("""
        \(owner) C {
            abstract fun f(): Int
            abstract val value: Int
            abstract var mutable: Int
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testEnumAbstractOverrideWithEntryImplementationRemainsValid() throws {
        let ctx = makeContextFromSource("""
        interface T { fun f() }
        enum class E : T {
            ENTRY {
                override fun f() {}
            };
            abstract override fun f()
        }
        """)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testEnumAbstractMemberWithEntryImplementationRemainsValid() throws {
        let ctx = makeContextFromSource("""
        enum class C {
            ENTRY {
                override fun f(): Int = 42
            };
            abstract fun f(): Int
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testUpstreamAbstractOverrideInEnumRemainsValid() throws {
        // Mirrors JetBrains/kotlin v2.3.10 compiler/testData/diagnostics/tests/enum/AbstractOverrideInEnum.kt.
        let ctx = makeContextFromSource("""
        enum class E : T {
            ENTRY {
                override fun f() {
                }
            };

            abstract override fun f()
        }

        interface T {
            fun f()
        }
        """)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        #expect(!ctx.diagnostics.hasError)
    }

    @Test func testEnumAbstractOverrideRequiresEveryEntryImplementation() throws {
        let ctx = makeContextFromSource("""
        interface T { fun f() }
        enum class E : T {
            IMPLEMENTED { override fun f() {} },
            MISSING;
            abstract override fun f()
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-ABSTRACT"
                && $0.severity == .error
                && $0.message.contains("E.MISSING")
        })
    }

    @Test func testEnumEntriesRequireInheritedRegularAndMemberExtensionImplementations() throws {
        let ctx = makeContextFromSource("""
        interface J { fun describe(): String }
        enum class G : J { A, B }

        interface I { fun Any?.describe(): String }
        enum class E : I { A, B }
        enum class CompleteExtension : I {
            A { override fun Any?.describe(): String = "ok" }
        }

        interface P { val label: String }
        enum class MissingProperties : P { A, B }
        enum class CompleteProperty : P {
            A { override val label: String = "ok" }
        }

        enum class OwnAbstract { A, B; abstract fun code(): Int }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .error
        }
        let entryNames = errors.compactMap { error -> String? in
            [
                "G.A", "G.B", "E.A", "E.B",
                "MissingProperties.A", "MissingProperties.B",
                "OwnAbstract.A", "OwnAbstract.B",
            ]
                .first { error.message.contains($0) }
        }
        #expect(errors.count == 8, "Expected one diagnostic per enum entry: \(errors)")
        #expect(Set(entryNames) == Set([
            "G.A", "G.B", "E.A", "E.B",
            "MissingProperties.A", "MissingProperties.B",
            "OwnAbstract.A", "OwnAbstract.B",
        ]))
        #expect(errors.allSatisfy { $0.message.contains("does not implement abstract member") })
    }

    @Test func testEnumEntriesAcceptInferredTypePropertyOverrides() throws {
        // Inferred-type `override val`s carry only the `Any?` placeholder when
        // the enum-entry completeness check runs; they must still count as
        // implementations just like explicitly typed overrides.
        let ctx = makeContextFromSource("""
        interface P { val label: String }
        enum class EntryOverride : P {
            A { override val label = "ok" }
        }
        enum class ClassOverride : P {
            A, B;
            override val label = "ok"
        }
        enum class OwnAbstract {
            A { override val label = "ok" };
            abstract val label: String
        }
        """)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .error
        }
        #expect(errors.isEmpty, "Expected no abstract-member diagnostics: \(errors)")
    }

    private static let abstractErrorSources: [String] = [
        """
        package sample0
        abstract class Shape {
            abstract fun area(): Double
        }
        fun main() {
            val s = Shape()  // Error: cannot instantiate abstract class
        }
        """,
        """
        package sample1
        abstract class Base {
            abstract fun test() { println("error") }  // Error: abstract function cannot have body
        }
        """,
        """
        package sample2
        abstract class Base {
            abstract val prop: String = "error"  // Error: abstract property cannot have initializer
        }
        """,
        """
        package sample3
        abstract class Base {
            private abstract fun test()  // Error: abstract member cannot be private
        }
        """,
        """
        package sample4
        abstract final class Base  // Error: class cannot be both abstract and final
        """,
        """
        package sample5
        sealed final class Base  // Error: class cannot be both sealed and final
        """,
        """
        package sample6
        abstract class Base {
            abstract fun test()
        }
        class Derived : Base() {
            // Error: must override abstract method
        }
        """,
        """
        package sample7
        abstract class Base {
            abstract var prop: String
                field = "error"  // Error: abstract property cannot have explicit backing field
        }
        """,
        """
        package sample8
        abstract class Base {
            abstract val prop: String by lazy { "error" }  // Error: abstract property cannot have delegate
        }
        """,
    ]

    private static let _sharedCtx = Result {
        try semaContext(for: abstractErrorSources)
    }

    @Test func testInvalidAbstractDeclarationsStillError() throws {
        let ctx = try Self._sharedCtx.get()

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(ctx.diagnostics.hasError)
    }

    @Test(arguments: [
        """
        expect abstract class CharsetEncoder
        actual abstract class CharsetEncoder
        abstract class PlainAbstract
        """,
        """
        abstract class ConcreteMembers {
            val value: Int = 1
            fun someMethod() {}
        }
        class Derived : ConcreteMembers()
        """,
        """
        abstract class AbstractOuter {
            abstract class NestedAbstract
        }
        class ConcreteOuter {
            abstract class NestedAbstract
        }
        """,
        """
        abstract class Base {
            abstract fun value(): Int
        }
        abstract class Implemented : Base() {
            override fun value(): Int = 1
        }
        class Derived : Implemented()
        """,
    ])
    func testAbstractClassWithoutAbstractMembersDoesNotWarn(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.isEmpty)
    }

    @Test func testEmptyAbstractClassCannotBeInstantiated() throws {
        let ctx = makeContextFromSource("""
        abstract class PlainAbstract
        fun main() {
            val instance = PlainAbstract()
        }
        """)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        #expect(
            ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .error }
        )
    }

    @Test func testSealedTypesWithoutAbstractMembers() throws {
        let sources = [
            """
            package sealedEmpty
            sealed class S
            class SA(val x: Int) : S()
            fun main() { println("ok") }
            """,
            """
            package sealedConcrete
            sealed class S {
                val value: Int = 42
                fun answer(): Int = value
            }
            class SA : S()
            """,
            """
            package sealedInterface
            sealed interface S
            class SA : S
            """,
            """
            package sealedNested
            abstract class Outer {
                abstract fun required(): Int
                sealed class Inner
                class Derived : Inner()
            }
            """,
            """
            package sealedOuter
            sealed class Outer {
                abstract class Inner
            }
            """,
            """
            package sealedContract
            sealed class S {
                abstract fun required(): Int
            }
            class SA : S()
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            for path in paths.prefix(4) {
                let diagnostics = diagnosticsForPath(path, in: ctx)
                #expect(!diagnostics.hasError)
                assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diagnostics)
            }

            // KUU-984 removed the "abstract class has no abstract members"
            // warning pass entirely, so nested abstract classes no longer warn.
            let nestedDiagnostics = diagnosticsForPath(paths[4], in: ctx)
            #expect(!nestedDiagnostics.hasError)
            assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: nestedDiagnostics)

            let contractDiagnostics = diagnosticsForPath(paths[5], in: ctx)
            #expect(contractDiagnostics.hasError)
            #expect(contractDiagnostics.contains {
                $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.severity == .error
            })
            #expect(!contractDiagnostics.contains { $0.severity == .warning })
        }
    }

    @Test func testAbstractMemberContentDiagnosticsMatchKotlincWording() throws {
        let ctx = makeContextFromSource("""
        abstract class C {
            abstract fun f() {}
            abstract fun g() = 1
            abstract val v = 1
            abstract val w by lazy { 1 }
            abstract val x: Int get() = 1
            abstract var y: Int get() = 2 set(v) {}
        }
        """)
        try runSema(ctx)

        let messages = ctx.diagnostics.diagnostics
            .filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
            .map(\.message)
        #expect(messages.contains("function 'f' with a body cannot be abstract."))
        #expect(messages.contains("function 'g' with a body cannot be abstract."))
        #expect(messages.contains("property with initializer cannot be abstract."))
        #expect(messages.contains("delegated property cannot be abstract."))
        #expect(messages.filter { $0 == "property with getter implementation cannot be abstract." }.count == 2)
        #expect(messages.contains("property with setter implementation cannot be abstract."))
    }

    @Test(arguments: ["class", "open class", "object"])
    func testAbstractPropertyContentSuppressedInNonAbstractOwner(owner: String) throws {
        // kotlinc still reports 'function with a body' in non-abstract owners
        // but lets 'abstract ... in non-abstract class' own property content.
        let ctx = makeContextFromSource("""
        \(owner) C {
            abstract val v = 1
            abstract fun f() {}
        }
        """)
        try runSema(ctx)

        let abstractDiags = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-SEMA-ABSTRACT" }
        #expect(abstractDiags.contains { $0.message == "function 'f' with a body cannot be abstract." })
        #expect(!abstractDiags.contains { $0.message.contains("property") })
    }

    @Test func testAbstractInterfacePropertyReportsContentNotInterfaceRules() throws {
        let ctx = makeContextFromSource("""
        interface I {
            abstract val v = 1
            abstract val w by lazy { 1 }
        }
        """)
        try runSema(ctx)

        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.message == "property with initializer cannot be abstract."
        })
        #expect(ctx.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-SEMA-ABSTRACT" && $0.message == "delegated property cannot be abstract."
        })
        assertNoDiagnostic("KSWIFTK-SEMA-0303", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-0304", in: ctx)
    }
}
#endif
