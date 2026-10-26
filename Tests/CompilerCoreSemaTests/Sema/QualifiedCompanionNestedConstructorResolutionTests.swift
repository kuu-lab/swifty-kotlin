@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct QualifiedCompanionNestedConstructorResolutionTests {
    private func makeLocalContext(_ source: String, includeStdlib: Bool = false) -> CompilationContext {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: includeStdlib)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    private func expectSelection(
        source: String,
        kind: SymbolKind,
        owner: [String],
        name: String = "B",
        includeStdlib: Bool = false
    ) throws {
        let ctx = makeLocalContext(source, includeStdlib: includeStdlib)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: name, in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        let chosenOwner = try #require(sema.symbols.parentSymbol(for: binding.chosenCallee))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == kind)
        #expect(sema.symbols.symbol(chosenOwner)?.fqName.map(ctx.interner.resolve) == owner)
        #expect(sema.bindings.isTypeQualifiedConstructorCallExpr(call) == (kind == .constructor))
    }

    @Test func exactIssueReproducerSelectsCompanionFunction() throws {
        let ctx = makeContextFromSource("""
        class A { companion object { fun B(x: Int) = 42 }; class B(val xs: List<String>) }
        fun main() { println(A.B(5)) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "B", in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        let companion = try #require(sema.symbols.lookup(fqName: ["A", "Companion"].map(ctx.interner.intern)))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .function)
        #expect(sema.symbols.parentSymbol(for: binding.chosenCallee) == companion)
        #expect(sema.bindings.exprType(for: call) == sema.types.intType)
        #expect(!sema.bindings.isTypeQualifiedConstructorCallExpr(call))
    }

    @Test(arguments: ["Companion", "Factory"])
    func namedAndDefaultCompanionsRemainCallable(companionName: String) throws {
        try expectSelection(source: """
        class A {
            companion object \(companionName) { fun B(x: Int): String = "factory" }
            class B(val value: String)
        }
        fun make(): String = A.B(5)
        """, kind: .function, owner: ["A", companionName])
    }

    @Test(arguments: ["Int", "Number", "Long", "Byte"])
    func applicableConstructorHasPriorityOverCompanionFunction(parameterType: String) throws {
        try expectSelection(source: """
        class A {
            companion object { fun B(value: Int): String = "factory" }
            class B(val value: \(parameterType))
        }
        fun make() = A.B(5)
        """, kind: .constructor, owner: ["A", "B"])
    }

    @Test func integerVariableDoesNotWidenToConstructorParameter() throws {
        try expectSelection(source: """
        class A {
            companion object { fun B(value: Int): String = "factory" }
            class B(val value: Long)
        }
        fun make(value: Int): String = A.B(value)
        """, kind: .function, owner: ["A", "Companion"])
    }

    @Test(arguments: ["A", "A.Companion"])
    func genericFactoryWithExplicitTypeArgumentAndNoValues(qualifier: String) throws {
        try expectSelection(source: """
        enum class Direction { NORTH }
        class A {
            companion object { inline fun <reified T : Enum<T>> Choice(): String = "factory" }
            class Choice<T : Any>(val choices: List<T>)
        }
        fun make(): String = \(qualifier).Choice<Direction>()
        """, kind: .function, owner: ["A", "Companion"], name: "Choice", includeStdlib: true)
    }

    @Test func genericConstructorRemainsSelectable() throws {
        try expectSelection(source: """
        class A {
            companion object { fun <T> Choice(): String = "factory" }
            class Choice<T>(val value: T)
        }
        fun make(): A.Choice<Int> = A.Choice<Int>(5)
        """, kind: .constructor, owner: ["A", "Choice"], name: "Choice")
    }

    @Test func explicitTypeArgumentsDoNotTakeNonGenericZeroArgumentShortcut() throws {
        try expectSelection(source: """
        class A {
            companion object { fun <T> B(): Int = 42 }
            class B
        }
        fun make(): Int = A.B<Int>()
        """, kind: .function, owner: ["A", "Companion"])
    }

    @Test(arguments: ["class B private constructor(val value: Int)", "private class B(val value: Int)"])
    func inaccessibleConstructorDoesNotHideCompanionFunction(declaration: String) throws {
        try expectSelection(source: """
        class A {
            companion object { fun B(value: Int): String = "factory" }
            \(declaration)
        }
        fun make(): String = A.B(5)
        """, kind: .function, owner: ["A", "Companion"])
    }

    @Test func inaccessibleFactoryDoesNotHideConstructor() throws {
        try expectSelection(source: """
        class A {
            companion object { private fun B(value: String): String = "factory" }
            class B(val value: Int)
        }
        fun make(): A.B = A.B(5)
        """, kind: .constructor, owner: ["A", "B"])
    }

    @Test func privateSecondaryConstructorDoesNotHidePublicConstructor() throws {
        try expectSelection(source: """
        class A {
            companion object { fun B(value: Int): String = "factory" }
            class B(val value: Int) { private constructor(value: String) : this(0) }
        }
        fun make(): A.B = A.B(5)
        """, kind: .constructor, owner: ["A", "B"])
    }

    @Test func selectedCompanionFunctionRetainsDeprecationDiagnostic() throws {
        let ctx = makeLocalContext("""
        class A {
            companion object { @Deprecated("factory") fun B(value: Int): Int = 42 }
            class B(val value: String)
        }
        fun make(): Int = A.B(5)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-DEPRECATED" })
    }

    @Test func inheritedCompanionFunctionRemainsCallable() throws {
        try expectSelection(source: """
        open class Base { fun B(value: Int): String = "factory" }
        class A {
            companion object : Base()
            class B(val value: String)
        }
        fun make(): String = A.B(5)
        """, kind: .function, owner: ["Base"])
    }

    @Test func companionExtensionRemainsCallable() throws {
        let ctx = makeLocalContext("""
        class A { companion object; class B(val value: String) }
        fun A.Companion.B(value: Int): Int = 42
        fun make(): Int = A.B(5)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "B", in: ast, interner: ctx.interner).first)
        let binding = try #require(sema.bindings.callBinding(for: call))
        #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .function)
        #expect(sema.symbols.symbol(binding.chosenCallee)?.fqName.map(ctx.interner.resolve) == ["B"])
        #expect(sema.bindings.exprType(for: call) == sema.types.intType)
    }

    @Test func incompatibleExpectedResultTypeDoesNotSelectFactory() throws {
        let ctx = makeLocalContext("""
        class A {
            companion object { fun B(value: Int): String = "factory" }
            class B(val value: Int)
        }
        fun make(): String = A.B(5)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "An applicable constructor must retain priority over the factory")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let call = try #require(memberCallExprIDs(named: "B", in: ast, interner: ctx.interner).first)
        if let binding = sema.bindings.callBinding(for: call) {
            #expect(sema.symbols.symbol(binding.chosenCallee)?.kind == .constructor)
        }
    }

    @Test(arguments: [false, true])
    func ambiguityIsPreserved(inConstructors: Bool) throws {
        let declarations = inConstructors ? """
        companion object { fun B(value: Any): String = "factory" }
        class B { constructor(value: Left); constructor(value: Right) }
        """ : """
        companion object {
            fun B(value: Left): String = "left"
            fun B(value: Right): String = "right"
        }
        class B(val value: String)
        """
        let ctx = makeLocalContext("""
        interface Left
        interface Right
        class Both : Left, Right
        class A { \(declarations) }
        fun make(value: Both) = A.B(value)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.filter { $0.code == "KSWIFTK-SEMA-0003" }.count == 1, "\(errors)")
        #expect(!errors.contains { $0.code == "KSWIFTK-SEMA-0002" }, "\(errors)")
    }

    @Test func unmatchedArgumentsStillFail() throws {
        let ctx = makeLocalContext("""
        class A {
            companion object { fun B(value: Int): String = "factory" }
            class B(val value: String)
        }
        fun make() = A.B(true)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0002" })
    }
}
