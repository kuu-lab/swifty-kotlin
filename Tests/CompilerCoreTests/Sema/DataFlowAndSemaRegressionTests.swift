#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - DataFlow + Sema Regression Tests

// Targets: DataFlow/BodyAnalysis.swift (45.8%)
//          DataFlow/HeaderCollection.swift (49.9%)
//          TypeCheck/TypeCheckSemaPhase.swift (51.4%)

@Suite
struct DataFlowAndSemaRegressionTests {
    // MARK: - BodyAnalysis: duplicate parameter name

    @Test func testDuplicateParameterNameEmitsDiagnostic() throws {
        let source = """
        fun bad(x: Int, x: Int): Int = x
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-TYPE-0002", in: ctx)
        }
    }

    // MARK: - BodyAnalysis: expression-body binding

    @Test func testExpressionBodyFunctionBindsReturnType() throws {
        let source = """
        fun answer(): Int = 42
        fun main() = answer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
            #expect(!exprTypesEmpty)
        }
    }

    // MARK: - BodyAnalysis: property decl binding

    @Test func testPropertyDeclBindsIdentifierAndType() throws {
        let source = """
        val greeting: String = "hello"
        fun main() = greeting
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let greetingSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "greeting"
            }
            #expect(greetingSymbol != nil)
        }
    }

    // MARK: - BodyAnalysis: resolveTypeRef nullable

    @Test func testNullableTypeAnnotationResolvesCorrectly() throws {
        let source = """
        fun nullable(x: Int?): Int? = x
        fun main() = nullable(null)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try #require(ctx.sema)
            let nullableSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "nullable"
            }
            #expect(nullableSymbol != nil)
            if let sym = nullableSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                #expect(sig.parameterTypes.count == 1)
            }
        }
    }

    // MARK: - BodyAnalysis: star projection (DEBT-SEMA-004)

    @Test func testStarProjectionInTypeAnnotationDoesNotCrashCompiler() throws {
        let source = """
        class Container<T>(val item: T)
        typealias OutContainer<T> = Container<out T>

        fun readStar(c: Container<*>): Any? = c.item
        fun eraseType(list: List<*>): Int = 0
        fun expandAlias(c: OutContainer<*>): Container<*> = c
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0063", in: ctx)
        }
    }

    // MARK: - BodyAnalysis: function type parameter

    @Test func testFunctionTypeParameterResolvesCorrectly() throws {
        let source = """
        fun apply(f: (Int) -> Int, x: Int): Int = f(x)
        fun main() = apply(f = { it -> it + 1 }, x = 5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let applySymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "apply"
            }
            #expect(applySymbol != nil)
        }
    }

    // MARK: - HeaderCollection: secondary constructor

    @Test func testSecondaryConstructorDefinesSymbol() throws {
        let source = """
        class Person(val name: String) {
            constructor(first: String, last: String): this(first)
        }
        fun main() = Person("Alice")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let ctorSymbols = sema.symbols.allSymbols().filter { symbol in
                symbol.kind == .constructor
            }
            #expect(ctorSymbols.count >= 2, "Expected primary + secondary constructor")
        }
    }

    // MARK: - HeaderCollection: enum class entries

    @Test func testEnumClassEntriesDefineFieldSymbols() throws {
        let source = """
        enum class Color { RED, GREEN, BLUE }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let fieldSymbols = sema.symbols.allSymbols().filter { symbol in
                symbol.kind == .field && (
                    ctx.interner.resolve(symbol.name) == "RED" ||
                        ctx.interner.resolve(symbol.name) == "GREEN" ||
                        ctx.interner.resolve(symbol.name) == "BLUE"
                )
            }
            #expect(fieldSymbols.count >= 1, "Expected at least 1 enum entry field")
        }
    }

    // MARK: - HeaderCollection: object declaration

    @Test func testObjectDeclarationDefinesSymbol() throws {
        let source = """
        object Singleton {
            val value: Int = 42
        }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let objectSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Singleton" && symbol.kind == .object
            }
            #expect(objectSymbol != nil)
        }
    }

    // MARK: - HeaderCollection: interface declaration

    @Test func testInterfaceDeclarationDefinesSymbol() throws {
        let source = """
        interface Greetable {
            fun greet(): String
        }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let interfaceSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Greetable" && symbol.kind == .interface
            }
            #expect(interfaceSymbol != nil)
        }
    }

    // MARK: - HeaderCollection: typeAlias declaration

    @Test func testTypeAliasDeclarationDefinesSymbol() throws {
        let source = """
        typealias Name = String
        fun greet(n: Name): String = n
        fun main() = greet("World")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let aliasSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "Name" && symbol.kind == .typeAlias
            }
            #expect(aliasSymbol != nil)
        }
    }

    // MARK: - HeaderCollection: extension function with receiver type

    @Test func testExtensionFunctionHasReceiverType() throws {
        let source = """
        fun String.shout(): String = this
        fun main() = "hello".shout()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let shoutSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "shout"
            }
            #expect(shoutSymbol != nil)
            if let sym = shoutSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                #expect(sig.receiverType != nil)
            }
        }
    }

    // MARK: - HeaderCollection: reified inline function

    @Test func testReifiedInlineFunctionDefinesTypeParameter() throws {
        let source = """
        inline fun <reified T> typeCheck(x: Any): Boolean = x is T
        fun main() = typeCheck<Int>(42)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let typeCheckSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "typeCheck"
            }
            #expect(typeCheckSymbol != nil)
            if let sym = typeCheckSymbol,
               let sig = sema.symbols.functionSignature(for: sym.id)
            {
                let reifiedEmpty = sig.reifiedTypeParameterIndices.isEmpty
                #expect(!reifiedEmpty)
            }
        }
    }

    // MARK: - HeaderCollection: reified on non-inline emits diagnostic

    @Test func testReifiedOnNonInlineFunctionEmitsDiagnostic() throws {
        let source = """
        fun <reified T> badReified(x: Any): Boolean = x is T
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0020", in: ctx)
        }
    }

    // MARK: - HeaderCollection: member functions and properties

    @Test func testClassMemberFunctionsAndPropertiesDefineSymbols() throws {
        let source = """
        class Counter {
            val count: Int = 0
            fun increment(): Int = count
        }
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            let incrementSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "increment"
            }
            #expect(incrementSymbol != nil)
            let countSymbol = sema.symbols.allSymbols().first { symbol in
                ctx.interner.resolve(symbol.name) == "count" && symbol.kind == .property
            }
            #expect(countSymbol != nil)
        }
    }

    // MARK: - HeaderCollection: duplicate declaration diagnostic

    @Test func testFixedAndTrailingVarargOverloadsDoNotConflict() throws {
        let source = """
        fun choose(a: Int, b: Int): Int = a
        fun choose(a: Int, vararg other: Int): Int = a
        fun main(): Int = choose(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
        }
    }

    @Test func testDuplicateTopLevelDeclarationEmitsDiagnostic() throws {
        let source = """
        val x: Int = 1
        val x: Int = 2
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
        }
    }

    // MARK: - HeaderCollection: KSP-CAP-006 (class + same-named top-level function)

    // Real kotlin-stdlib idiom (e.g. `class Random` + `fun Random(seed: Long): Random`):
    // a class and a same-named top-level function must coexist regardless of which
    // one is declared first in source order.

    @Test func testClassThenSameNamedFunctionDoesNotConflict() throws {
        let source = """
        class Box(val value: Int)
        fun Box(seed: Long): Box = Box(seed.toInt())
        fun main(): Int = Box(1L).value
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
        }
    }

    @Test func testFunctionThenSameNamedClassDoesNotConflict() throws {
        // The return type is deliberately not `Box` here: a same-file
        // function-signature forward reference to a later-declared type is a
        // separate, pre-existing limitation (BUG-141) unrelated to the
        // declaration-conflict check this test targets.
        let source = """
        fun Box(seed: Long): Int = seed.toInt()
        class Box(val value: Int)
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
        }
    }

    @Test func testDuplicateClassDeclarationStillConflicts() throws {
        // Guards against over-loosening: two nominal types of the same name
        // (as opposed to a nominal type + a callable) must still conflict.
        let source = """
        class Box(val value: Int)
        class Box(val other: Int)
        fun main(): Int = 0
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
        }
    }

    @Test func testCallResolutionMergesConstructorAndSameNamedFunctionCandidates() throws {
        // Before the KSP-CAP-006 fix, the class's constructors were only
        // considered as call candidates when no top-level function of the
        // same name existed at all -- so once `fun Box(seed: Long)` was
        // found, `Box(Int)` constructor calls (including this one, made from
        // inside the function's own body) failed with
        // "No viable overload found for call" even though the argument type
        // unambiguously matched the constructor.
        let source = """
        class Box(val value: Int)
        fun Box(seed: Long): Box = Box(seed.toInt() + 1000)
        fun main(): Int {
            val viaFunction = Box(5L)
            val viaConstructor = Box(7)
            return viaFunction.value + viaConstructor.value
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        }
    }

    @Test func testAbstractClassInstantiationStillErrorsWithoutCoexistingFunction() throws {
        // Guards against over-loosening the P5-112 abstract-instantiation
        // check: when no coexisting top-level function offers a viable
        // candidate, calling an abstract class's own name must still error.
        let source = """
        abstract class Shape {
            abstract fun area(): Double
        }
        fun main() {
            val s = Shape()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
        }
    }

    @Test func testAbstractClassYieldsToCoexistingFactoryFunction() throws {
        // Mirrors the real kotlin.random.Random shape: an abstract class
        // whose only usable "constructor-like" call target is a coexisting
        // top-level factory function. The abstract-instantiation diagnostic
        // must not fire when the factory function is a viable candidate.
        let source = """
        abstract class Shape {
            abstract fun area(): Double
        }
        class Circle(val radius: Double) : Shape() {
            override fun area(): Double = radius * radius * 3.14159
        }
        fun Shape(radius: Double): Shape = Circle(radius)
        fun main(): Double = Shape(2.0).area()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
        }
    }

    @Test func testSyntheticClassConstructorMatchingFactoryFunctionSignatureIsNotAmbiguous() throws {
        // Regression test for a bug the KSP-CAP-006 merge fix itself
        // introduced and then had to correct: `kotlin.io.path.Path` is
        // registered as a synthetic class whose own (synthetic) constructor
        // has the exact same signature, `(String) -> Path`, as the
        // coexisting top-level factory function `fun Path(pathString:
        // String): Path`. Naively merging the constructor into the call
        // candidate set produced two indistinguishable overloads, so every
        // `Path(...)` call resolved to `<error>` instead of picking the
        // (equally valid) function. The fix de-duplicates by parameter
        // signature before merging; this pins that behavior using the real
        // bundled stub rather than a hand-rolled reproduction.
        let source = """
        import kotlin.io.path.Path

        fun makePath(raw: String): Path = Path(raw)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0001", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0002", in: ctx)
            assertNoDiagnostic("KSWIFTK-SEMA-0023", in: ctx)
        }
    }

    // MARK: - BodyAnalysis: structural recursion depth guard

    @Test func testDeeplyNestedGenericTypeRefEmitsDepthDiagnostic() throws {
        let interner = StringInterner()
        let listName = interner.intern("List")
        let intName = interner.intern("Int")

        let symbols = SymbolTable()
        _ = symbols.define(
            kind: .class,
            name: listName,
            fqName: [listName],
            declSite: nil,
            visibility: .public
        )

        let types = TypeSystem()
        let diagnostics = DiagnosticEngine()
        let arena = ASTArena()

        var innerRef = arena.appendTypeRef(.named(path: [intName], args: [], nullable: false))
        for _ in 0..<600 {
            let arg = TypeArgRef.invariant(innerRef)
            innerRef = arena.appendTypeRef(.named(path: [listName], args: [arg], nullable: false))
        }

        let ast = ASTModule(files: [], arena: arena, declarationCount: 0, tokenCount: 0)
        let phase = DataFlowSemaPhase()
        _ = phase.resolveTypeRef(
            innerRef,
            ast: ast,
            symbols: symbols,
            types: types,
            interner: interner,
            diagnostics: diagnostics
        )

        #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-TYPE-DEPTH" })
    }

    // KNOWN GAP (DEBT-SEMA-003): self-referential top-level initializers are
    // currently accepted although kotlinc reports use before initialization.
    @Test func testSelfReferentialTopLevelInitializerIsNotYetDetected() throws {
        let source = """
        val cyclic: List<*> = listOf(cyclic)
        fun main() {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.isEmpty, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }
}
#endif
