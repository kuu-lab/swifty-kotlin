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

    /// KUU-4192: Kotlin ranks an explicit single-name import above
    /// same-package declarations for values too, not only classifiers
    /// (KUU-1423). kotlinx-coroutines hits this with
    /// `import Channel.Factory.BUFFERED` (an `Int` const) losing to the
    /// same-package `internal val BUFFERED = Symbol(...)` in
    /// BufferedChannel.kt, which made `BUFFERED ->` when-branches report
    /// KSWIFTK-SEMA-0466.
    @Test(arguments: [false, true])
    func explicitImportValueShadowsSamePackageValue(separateFile: Bool) throws {
        let declarations = """
        internal class CellSymbol(val name: String)

        internal val BUFFERED = CellSymbol("BUFFERED")

        object ChannelFactory {
            const val BUFFERED: Int = -2
        }
        """
        let uses = """
        fun pick(capacity: Int): Int = when (capacity) {
            BUFFERED -> 1
            else -> 0
        }
        fun direct(): Int {
            val x: Int = BUFFERED
            return x
        }
        """
        let sources = separateFile
            ? ["package demo\n" + declarations,
               "package demo\nimport demo.ChannelFactory.BUFFERED\n" + uses]
            : ["package demo\nimport demo.ChannelFactory.BUFFERED\n" + declarations + "\n" + uses]

        try withTemporaryFiles(contents: sources) { paths in
            let context = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(context)
            #expect(!context.diagnostics.hasError, "\(context.diagnostics.diagnostics)")
            let sema = try #require(context.sema)
            let importedConst = try #require(sema.symbols.lookup(
                fqName: ["demo", "ChannelFactory", "BUFFERED"].map { context.interner.intern($0) }
            ))
            let packageValue = try #require(sema.symbols.lookup(
                fqName: ["demo", "BUFFERED"].map { context.interner.intern($0) }
            ))
            let ast = try #require(context.ast)
            let referencedSymbols = Set(ast.arena.exprs.indices.compactMap { index in
                sema.bindings.identifierSymbol(for: ExprID(rawValue: Int32(index)))
            })
            #expect(referencedSymbols.contains(importedConst))
            #expect(!referencedSymbols.contains(packageValue))
        }
    }
}
