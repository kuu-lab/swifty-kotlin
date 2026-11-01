@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

@Suite
struct ValueNameScopeResolutionTests {
    @Test
    func classifiersWithoutValuesDoNotHideOuterValues() throws {
        let source = """
        interface Marker
        object Pick : Marker
        open class Parent { interface Pick }
        class Child : Parent() {
            val picked: Marker = Pick
            fun local(): String { val Pick = "local"; return Pick }
            fun qualified(value: Parent.Pick?): Parent.Pick? = value
        }

        object HasCompanion : Marker
        open class ParentTwo { class HasCompanion { companion object : Marker } }
        class ChildTwo : ParentTwo() { val picked: Marker = HasCompanion }

        object InnerObject : Marker
        open class ParentThree { object InnerObject : Marker }
        class ChildThree : ParentThree() { val picked: Marker = InnerObject }

        object Actual : Marker
        typealias Alias = Actual
        open class ParentFour { interface Alias }
        class ChildFour : ParentFour() { val picked: Marker = Alias }

        object T
        fun <T> typeParameterDoesNotHideValue(): Any = T

        object FunctionName
        class FunctionOwner {
            fun FunctionName(): Int = 1
            fun value(): Any = FunctionName
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let ast = try #require(context.ast)
            let sema = try #require(context.sema)
            let symbolPaths = [
                ["Pick"], ["ParentTwo", "HasCompanion"],
                ["ParentThree", "InnerObject"], ["Actual"], ["T"], ["FunctionName"],
            ]
            let expected = try symbolPaths.map { path in
                try #require(sema.symbols.lookup(fqName: path.map(context.interner.intern)))
            }
            let referencedSymbols = Set(ast.arena.exprs.indices.compactMap { index in
                sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(index)))
            })
            for symbol in expected {
                #expect(referencedSymbols.contains(symbol))
            }
        }
    }

    @Test
    func unrelatedObjectIsStillRejectedForTypedProperty() throws {
        let source = """
        interface Marker
        object Wrong
        open class Parent { interface Wrong }
        class Child : Parent() { val picked: Marker = Wrong }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0468" })
        }
    }

    @Test
    func qualifierStillSelectsTheNestedClassifier() throws {
        let source = """
        object Pick { val answer = 7 }
        open class Parent { interface Pick }
        class Child : Parent() { fun answer() = Pick.answer }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)
            #expect(context.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0024" })
        }
    }
}
