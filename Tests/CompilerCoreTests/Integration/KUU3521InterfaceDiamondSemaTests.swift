@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct KUU3521InterfaceDiamondSemaTests {
    @Test
    func subinterfaceOverrideSatisfiesDirectParentDiamond() throws {
        let source = """
        interface BK { fun foo(): String = "10" }
        interface KTrait: BK { override fun foo() = "30" }
        class A : BK, KTrait {}

        interface Base { fun bar(): String = "base" }
        interface Left: Base { override fun bar() = "left" }
        interface Right: Base { override fun bar() = "right" }
        class Diamond: Left, Right {}

        fun main() { println(A().foo()) }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let diamondConflicts = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0171"
            }
            #expect(diamondConflicts.count == 1)
            #expect(diamondConflicts.first?.message.contains("class 'Diamond'") == true)

            let unexpectedErrors = ctx.diagnostics.diagnostics.filter {
                $0.severity == .error && $0.code != "KSWIFTK-SEMA-0171"
            }
            #expect(unexpectedErrors.isEmpty, "Unexpected diagnostics: \(unexpectedErrors)")
        }
    }

    @Test
    func mixedAbstractAndConcreteInterfaceMethodsRequireOverride() throws {
        let source = """
        interface I1 { fun g(): Int }
        interface I2 { fun g(): Int = 2 }
        class E : I1, I2
        class F : I1, I2 { override fun g() = 3 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let conflicts = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0171"
            }
            #expect(conflicts.count == 1)
            #expect(conflicts.first?.message == "class 'E' must override 'g' because it inherits multiple interface methods for it.")
        }
    }

    @Test
    func pureAbstractInterfaceCollisionStaysOnAbstractMemberPath() throws {
        let source = """
        interface I1 { fun g(): Int }
        interface I3 { fun g(): Int }
        class E : I1, I3
        abstract class AC : I1, I3
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0171" }))
            let abstractErrors = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-ABSTRACT"
            }
            #expect(abstractErrors.count == 1)
        }
    }

    @Test
    func abstractClassObjectAndInterfaceAlsoRequireDiamondOverride() throws {
        let source = """
        interface I1 { fun g(): Int }
        interface I2 { fun g(): Int = 2 }
        object O : I1, I2
        abstract class AC : I1, I2
        interface J : I1, I2
        interface Resolved : I1, I2 { override fun g(): Int }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let conflicts = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0171"
            }
            #expect(conflicts.map(\.message).sorted() == [
                "class 'AC' must override 'g' because it inherits multiple interface methods for it.",
                "interface 'J' must override 'g' because it inherits multiple interface methods for it.",
                "object 'O' must override 'g' because it inherits multiple interface methods for it.",
            ])
        }
    }

    @Test
    func nestedObjectDiamondUsesEnclosingQualifiedName() throws {
        let source = """
        interface I1 { fun g(): Int }
        interface I2 { fun g(): Int = 2 }
        class Outer { object Inner : I1, I2 }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let conflicts = ctx.diagnostics.diagnostics.filter {
                $0.code == "KSWIFTK-SEMA-0171"
            }
            #expect(conflicts.count == 1)
            #expect(conflicts.first?.message == "object 'Outer.Inner' must override 'g' because it inherits multiple interface methods for it.")
        }
    }
}
