@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct InheritedInterfaceQualifierTests {
    private func context(_ source: String) -> CompilationContext {
        let path = "/virtual/inherited-interface-qualifier.kt"
        let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        return ctx
    }

    @Test(arguments: [false, true])
    func outerObjectWinsOverInheritedInterfaceClassifier(hasCompanion: Bool) throws {
        let companion = hasCompanion ? "companion object { val Key: Int = 7 }" : ""
        let ctx = context("""
        interface Root { interface Element : Root { \(companion) } }
        open class Base : Root.Element
        object Element { val Key: Int = 42 }
        class Child : Base() { fun lookup(): Int = Element.Key }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let name = ctx.interner.intern("Element")
        let qualifier = try #require(firstExprID(in: ast) { _, expr in
            if case let .nameRef(candidate, _) = expr { return candidate == name }
            return false
        })
        let object = try #require(sema.symbols.lookup(fqName: [name]))
        #expect(sema.bindings.identifierSymbol(for: qualifier) == object)
    }

    @Test
    func inheritedClassAndLexicalClassifiersRemainVisible() throws {
        let ctx = context("""
        open class Base { class Nested { companion object { val Key: Int = 13 } } }
        class Child : Base() { fun lookup(): Int = Nested.Key }
        interface Lexical {
            interface Local { companion object { val Key: Int = 17 } }
            fun lookup(): Int = Local.Key
        }
        fun qualified(): Int = Lexical.Local.Key
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func objectAliasAndLocalValueRemainVisible() throws {
        let ctx = context("""
        interface Root { interface Element : Root }
        open class Base : Root.Element
        object Element { val Key: Int = 42 }
        typealias Alias = Element
        class Holder(val Key: Int)
        class Child : Base() {
            fun alias(): Int = Alias.Key
            fun local(): Int { val Element = Holder(99); return Element.Key }
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func bareValueAndSafeCallUseTheOuterObject() throws {
        let ctx = context("""
        interface Root { interface Element : Root }
        open class Base : Root.Element
        object Element { val Key: Int = 42 }
        class Child : Base() {
            fun bare(): Any = Element
            fun safe(): Int = Element?.Key ?: 0
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let name = ctx.interner.intern("Element")
        let object = try #require(sema.symbols.lookup(fqName: [name]))
        let references = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let id = ExprID(rawValue: Int32(index))
            guard case let .nameRef(candidate, _) = ast.arena.expr(id), candidate == name else { return nil }
            return id
        }
        #expect(references.count == 2)
        #expect(references.allSatisfy { sema.bindings.identifierSymbol(for: $0) == object })
    }

    @Test
    func normalObjectCompanionAndInheritedClassConstructorRemainUsable() throws {
        let ctx = context("""
        interface Root { interface Factory : Root; interface Normal }
        open class Base : Root.Factory { class Nested { val value = 13 } }
        object Normal { val value = 8 }
        class Factory { companion object { val value = 9 } }
        class Callable { companion object { operator fun invoke(arg: Int): Int = arg } }
        class Child : Base() {
            fun companionValue(): Boolean = Factory === Factory.Companion
            fun companionMember(): Int = Factory.value
            fun companionInvoke(): Int = Callable(5)
            fun nestedConstructor(): Int = Nested().value
            fun objectValue(): Boolean = Normal === Normal
            fun objectMember(): Int = Normal.value
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitlyImportedInterfaceClassifierRemainsVisible() throws {
        let ctx = context("""
        import Root.Element
        interface Root { interface Element { companion object { val Key: Int = 23 } } }
        interface Other { interface Element }
        class Child : Other { fun lookup(): Int = Element.Key }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let ast = try #require(ctx.ast)
        let name = ctx.interner.intern("Element")
        let qualifier = try #require(firstExprID(in: ast) { _, expr in
            if case let .nameRef(candidate, _) = expr { return candidate == name }
            return false
        })
        let imported = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Root"), name]))
        #expect(sema.bindings.identifierSymbol(for: qualifier) == imported)
    }

    @Test
    func missingOuterQualifierRemainsUnresolved() throws {
        let ctx = context("""
        interface Root { interface Element : Root { companion object { val Key: Int = 7 } } }
        open class Base : Root.Element
        class Child : Base() { fun lookup(): Int = Element.Key }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "An inherited interface classifier is not a qualifier")
    }

    @Test
    func typeAliasDoesNotExposeNestedClassifier() throws {
        let ctx = context("""
        interface Root { interface Element }
        typealias Alias = Root
        class Item : Alias.Element
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "A typealias cannot qualify a nested classifier")
    }

    @Test
    func inheritedClassifierDoesNotHideAliasNestedAccessRejection() throws {
        let ctx = context("""
        interface Root { interface Alias : Root }
        open class Base : Root.Alias
        class Outer { class Nested { companion object { val Key = 23 } }; companion object }
        typealias Alias = Outer
        class Child : Base() { fun invalid(): Int = Alias.Nested.Key }
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "An alias still cannot qualify a nested classifier")
    }

    @Test
    func aliasCompanionMemberRemainsVisibleDespiteInheritedName() throws {
        let ctx = context("""
        interface Root { interface Alias : Root }
        open class Base : Root.Alias
        class Outer { companion object { val Key: Int = 23 } }
        typealias Alias = Outer
        class Child : Base() { fun valid(): Int = Alias.Key }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }
}
