#if canImport(Testing)
import Foundation
import Testing
@testable import CompilerCore

@Suite struct InheritanceModifierTests {

    @Test func testInheritanceModifierSema() throws {
        let sources: [String] = [
            // testAbstractOverrideInAbstractClass
            """
            package sample0
                    abstract class Shape {
                        abstract fun area(): Double
                        open fun describe(): String = "Shape"
                    }

                    abstract class Circle : Shape() {
                        abstract override fun area(): Double
                        abstract override fun describe(): String
                    }

            """,

            // testAbstractOverrideInConcreteClass
            """
            package sample1
                    open class Shape {
                        open fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        abstract override fun describe(): String
                    }

            """,

            // testAbstractOverrideOfAbstractMember
            """
            package sample2
                    abstract class Shape {
                        abstract fun area(): Double
                    }

                    abstract class Circle : Shape() {
                        abstract override fun area(): Double
                    }

            """,

            // testFinalOverrideValid
            """
            package sample3
                    open class Shape {
                        open fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        final override fun describe(): String = "Circle"
                    }

            """,

            // testFinalOverrideCannotBeFurtherOverridden
            """
            package sample4
                    open class Shape {
                        open fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        final override fun describe(): String = "Circle"
                    }

                    class ColoredCircle : Circle() {
                        override fun describe(): String = "Colored Circle"
                    }

            """,

            // testAbstractFinalConflict
            """
            package sample5
                    abstract class Shape {
                        abstract final fun area(): Double
                    }

            """,

            // testInterfaceMemberCannotBeFinal
            """
            package sample6
                    interface Shape {
                        final fun area(): Double
                    }

            """,

            // testInterfaceAbstractRedundant
            """
            package sample7
                    interface Shape {
                        abstract fun area(): Double
                    }

            """,

            // testDataClassCannotHaveOpenMembers
            """
            package sample8
                    data class Point(val x: Int, val y: Int) {
                        open fun distance(): Double = 0.0
                    }

            """,

            // testOverrideWithLessVisibility
            """
            package sample9
                    open class Shape {
                        public fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        protected override fun describe(): String = "Circle"
                    }

            """,

            // testOverrideWithSameVisibility
            """
            package sample10
                    open class Shape {
                        protected open fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        protected override fun describe(): String = "Circle"
                    }

            """,

            // testOverrideWithMoreVisibility
            """
            package sample11
                    open class Shape {
                        protected open fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        public override fun describe(): String = "Circle"
                    }

            """,

            // testInternalOverrideOfPublicInSameModule
            """
            package sample12
                    open class Shape {
                        open fun describe(): String = "Shape"
                    }

                    class Circle : Shape() {
                        internal override fun describe(): String = "Circle"
                    }

            """,

            // testOverrideWithCovariantReturnType
            """
            package sample13
                    open class Animal
                    class Dog : Animal()

                    open class Factory {
                        open fun create(): Animal = Animal()
                    }

                    class DogFactory : Factory() {
                        override fun create(): Dog = Dog()
                    }

            """,

            // testOverrideWithIncompatibleReturnType
            """
            package sample14
                    open class Animal
                    open class Plant

                    open class Factory {
                        open fun create(): Animal = Animal()
                    }

                    class PlantFactory : Factory() {
                        override fun create(): Plant = Plant()
                    }

            """,

            // testComplexInheritanceHierarchy
            """
            package sample15
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

            """,

            // testOverrideChaining
            """
            package sample16
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
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            // testAbstractOverrideInAbstractClass

            do {
                let sample0Path = paths[0]
                let sampleDiags = diagnosticsForPath(sample0Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testAbstractOverrideInConcreteClass

            do {
                let sample1Path = paths[1]
                let sampleDiags = diagnosticsForPath(sample1Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: sampleDiags)

            }
            // testAbstractOverrideOfAbstractMember

            do {
                let sample2Path = paths[2]
                let sampleDiags = diagnosticsForPath(sample2Path, in: ctx)


                        // Kotlin allows an abstract class to keep an inherited abstract member abstract.
                        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testFinalOverrideValid

            do {
                let sample3Path = paths[3]
                let sampleDiags = diagnosticsForPath(sample3Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testFinalOverrideCannotBeFurtherOverridden

            do {
                let sample4Path = paths[4]
                let sampleDiags = diagnosticsForPath(sample4Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-FINAL", in: sampleDiags)

            }
            // testAbstractFinalConflict

            do {
                let sample5Path = paths[5]
                let sampleDiags = diagnosticsForPath(sample5Path, in: ctx)


                        // Class-level abstract/final conflict is currently reported by abstract-class validation.
                        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: sampleDiags)

            }
            // testInterfaceMemberCannotBeFinal

            do {
                let sample6Path = paths[6]
                let sampleDiags = diagnosticsForPath(sample6Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: sampleDiags)

            }
            // testInterfaceAbstractRedundant

            do {
                let sample7Path = paths[7]
                let sampleDiags = diagnosticsForPath(sample7Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-REDUNDANT-MODIFIER", in: sampleDiags)

            }
            // testDataClassCannotHaveOpenMembers

            do {
                let sample8Path = paths[8]
                let sampleDiags = diagnosticsForPath(sample8Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: sampleDiags)

            }
            // testOverrideWithLessVisibility

            do {
                let sample9Path = paths[9]
                let sampleDiags = diagnosticsForPath(sample9Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: sampleDiags)

            }
            // testOverrideWithSameVisibility

            do {
                let sample10Path = paths[10]
                let sampleDiags = diagnosticsForPath(sample10Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testOverrideWithMoreVisibility

            do {
                let sample11Path = paths[11]
                let sampleDiags = diagnosticsForPath(sample11Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testInternalOverrideOfPublicInSameModule

            do {
                let sample12Path = paths[12]
                let sampleDiags = diagnosticsForPath(sample12Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-VISIBILITY-MODULE", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testOverrideWithCovariantReturnType

            do {
                let sample13Path = paths[13]
                let sampleDiags = diagnosticsForPath(sample13Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testOverrideWithIncompatibleReturnType

            do {
                let sample14Path = paths[14]
                let sampleDiags = diagnosticsForPath(sample14Path, in: ctx)


                        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-RETURN", in: sampleDiags)

            }
            // testComplexInheritanceHierarchy

            do {
                let sample15Path = paths[15]
                let sampleDiags = diagnosticsForPath(sample15Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT-OVERRIDE", in: sampleDiags)
                        assertNoDiagnostic("KSWIFTK-SEMA-MODIFIER-CONFLICT", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }
            // testOverrideChaining

            do {
                let sample16Path = paths[16]
                let sampleDiags = diagnosticsForPath(sample16Path, in: ctx)


                        assertNoDiagnostic("KSWIFTK-SEMA-FINAL", in: sampleDiags)
                        #expect(!(sampleDiags.contains(where: { $0.severity == .error })))

            }

        }
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

}
#endif
