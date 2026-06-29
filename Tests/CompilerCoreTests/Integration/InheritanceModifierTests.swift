#if canImport(Testing)
import Foundation
import Testing
@testable import CompilerCore

@Suite struct InheritanceModifierTests {

    // MARK: - Abstract Override Tests

    @Test func testAbstractOverrideInAbstractClass() throws {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
            open fun describe(): String = "Shape"
        }

        abstract class Circle : Shape() {
            abstract override fun area(): Double
            abstract override fun describe(): String
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testAbstractOverrideInConcreteClass() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            abstract override fun describe(): String
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
    }

    @Test func testAbstractOverrideOfAbstractMember() throws {
        let source = """
        abstract class Shape {
            abstract fun area(): Double
        }

        abstract class Circle : Shape() {
            abstract override fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Kotlin allows an abstract class to keep an inherited abstract member abstract.
        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    // MARK: - Final Override Tests

    @Test func testFinalOverrideValid() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            final override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testFinalOverrideCannotBeFurtherOverridden() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            final override fun describe(): String = "Circle"
        }

        class ColoredCircle : Circle() {
            override fun describe(): String = "Colored Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
    }

    // MARK: - Modifier Combination Tests

    @Test func testAbstractFinalConflict() throws {
        let source = """
        abstract class Shape {
            abstract final fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        // Class-level abstract/final conflict is currently reported by abstract-class validation.
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
    }

    @Test func testInterfaceMemberCannotBeFinal() throws {
        let source = """
        interface Shape {
            final fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
    }

    @Test func testInterfaceAbstractRedundant() throws {
        let source = """
        interface Shape {
            abstract fun area(): Double
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-REDUNDANT-MODIFIER", in: ctx)
    }

    @Test func testDataClassCannotHaveOpenMembers() throws {
        let source = """
        data class Point(val x: Int, val y: Int) {
            open fun distance(): Double = 0.0
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
    }

    // MARK: - Visibility Constraint Tests

    @Test func testOverrideWithLessVisibility() throws {
        let source = """
        open class Shape {
            public fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            protected override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: ctx)
    }

    @Test func testOverrideWithSameVisibility() throws {
        let source = """
        open class Shape {
            protected open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            protected override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testOverrideWithMoreVisibility() throws {
        let source = """
        open class Shape {
            protected open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            public override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testInternalOverrideOfPublicInSameModule() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            internal override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY-MODULE", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testInternalOverrideOfPublicFromOtherModule() throws {
        let source = """
        open class Shape {
            open fun describe(): String = "Shape"
        }

        class Circle : Shape() {
            internal override fun describe(): String = "Circle"
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let phase = DataFlowSemaPhase()
        let symbols = SymbolTable()
        let types = TypeSystem()
        types.symbolTable = symbols
        let bindings = BindingTable()
        let fileScopes = phase.buildFileScopes(
            ast: try #require(ctx.ast),
            symbols: symbols,
            interner: ctx.interner
        )
        phase.collectAllHeaders(
            ast: try #require(ctx.ast),
            fileScopes: fileScopes,
            symbols: symbols,
            types: types,
            bindings: bindings,
            ctx: ctx
        )
        phase.assignCompilationModuleFQNames(
            symbols: symbols,
            moduleName: ctx.options.moduleName,
            interner: ctx.interner
        )
        phase.bindInheritanceEdges(
            ast: try #require(ctx.ast),
            symbols: symbols,
            bindings: bindings,
            types: types,
            interner: ctx.interner
        )

        guard let shapeSymbol = symbols.allSymbols().first(where: {
            ctx.interner.resolve($0.name) == "Shape" && $0.kind == .class
        }) else {
            Issue.record("Shape symbol not found")
            return
        }
        let otherModule = ctx.interner.intern("OtherModule")
        symbols.setModuleFQN(otherModule, for: shapeSymbol.id)
        if let describeSymbol = symbols.children(ofFQName: shapeSymbol.fqName).compactMap({ symbols.symbol($0) }).first(where: {
            ctx.interner.resolve($0.name) == "describe" && $0.kind == .function
        }) {
            symbols.setModuleFQN(otherModule, for: describeSymbol.id)
        }

        phase.validateOpenFinalOverride(
            ast: try #require(ctx.ast),
            symbols: symbols,
            bindings: bindings,
            types: types,
            diagnostics: ctx.diagnostics,
            interner: ctx.interner,
            compilationModuleName: ctx.options.moduleName
        )

        assertHasDiagnostic("KSWIFTK-SEMA-VISIBILITY-MODULE", in: ctx)
    }

    @Test func testImportedLibrarySymbolsReceiveModuleFQN() throws {
        let fm = FileManager.default
        let libDir = fm.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("kklib")
        try fm.createDirectory(at: libDir, withIntermediateDirectories: true)

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "BaseLib",
          "metadata": "metadata.bin"
        }
        """
        let metadata = """
        symbols=1
        class _kk_Base fq=base.Base schema=v1 fields=0 layoutWords=2 vtable=0 itable=0
        """
        try manifest.write(to: libDir.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try metadata.write(to: libDir.appendingPathComponent("metadata.bin"), atomically: true, encoding: .utf8)

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "DerivedLib",
                emit: .kirDump,
                searchPaths: [libDir.path]
            )

            let symbols = SymbolTable()
            let types = TypeSystem()
            let diagnostics = DiagnosticEngine()
            var inlineFns: [SymbolID: KIRFunction] = [:]
            DataFlowSemaPhase().loadImportedLibrarySymbols(
                options: ctx.options,
                symbols: symbols,
                types: types,
                diagnostics: diagnostics,
                interner: ctx.interner,
                importedInlineFunctions: &inlineFns
            )

            let baseSymbol = symbols.allSymbols().first {
                ctx.interner.resolve($0.name) == "Base" && $0.kind == .class
            }
            #expect(baseSymbol != nil)
            #expect(
                ctx.interner.resolve(symbols.moduleFQN(for: baseSymbol!.id)!) == "BaseLib"
            )
        }
    }

    @Test func testOverrideWithCovariantReturnType() throws {
        let source = """
        open class Animal
        class Dog : Animal()

        open class Factory {
            open fun create(): Animal = Animal()
        }

        class DogFactory : Factory() {
            override fun create(): Dog = Dog()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testOverrideWithIncompatibleReturnType() throws {
        let source = """
        open class Animal
        open class Plant

        open class Factory {
            open fun create(): Animal = Animal()
        }

        class PlantFactory : Factory() {
            override fun create(): Plant = Plant()
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: ctx)
    }

    // MARK: - Complex Inheritance Scenarios

    @Test func testComplexInheritanceHierarchy() throws {
        let source = """
        abstract class Animal {
            abstract fun makeSound(): String
            open fun move(): String = "moving"
        }

        abstract class Mammal : Animal() {
            abstract override fun makeSound(): String
            final override fun move(): String = "mammal moving"
        }

        class Dog : Mammal() {
            override fun makeSound(): String = "woof"
            // Cannot override move() because it's final in Mammal
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: ctx)
        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

    @Test func testOverrideChaining() throws {
        let source = """
        open class Base {
            open fun method(): String = "base"
        }

        open class Middle : Base() {
            override fun method(): String = "middle" // Implicitly open
        }

        class Derived : Middle() {
            final override fun method(): String = "derived" // Final override
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: ctx)
        #expect(!(ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error })))
    }

}
#endif
