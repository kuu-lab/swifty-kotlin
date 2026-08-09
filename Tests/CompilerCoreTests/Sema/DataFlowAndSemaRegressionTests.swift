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

    // MARK: - BodyAnalysis: expression-body binding

    // MARK: - BodyAnalysis: property decl binding

    // MARK: - BodyAnalysis: resolveTypeRef nullable

    // MARK: - BodyAnalysis: star projection (DEBT-SEMA-004)

    // MARK: - BodyAnalysis: function type parameter

    // MARK: - HeaderCollection: secondary constructor

    // MARK: - HeaderCollection: enum class entries

    // MARK: - HeaderCollection: object declaration

    // MARK: - HeaderCollection: interface declaration

    // MARK: - HeaderCollection: typeAlias declaration

    // MARK: - HeaderCollection: extension function with receiver type

    // MARK: - HeaderCollection: reified inline function

    // MARK: - HeaderCollection: reified on non-inline emits diagnostic

    // MARK: - HeaderCollection: member functions and properties

    // MARK: - HeaderCollection: duplicate declaration diagnostic

    // MARK: - HeaderCollection: KSP-CAP-006 (class + same-named top-level function)

    // Real kotlin-stdlib idiom (e.g. `class Random` + `fun Random(seed: Long): Random`):
    // a class and a same-named top-level function must coexist regardless of which
    // one is declared first in source order.

    // MARK: - BodyAnalysis: structural recursion depth guard

    private func nestedListParameterSource(depth: Int) -> String {
        let type = String(repeating: "List<", count: depth)
            + "Int"
            + String(repeating: ">", count: depth)
        return "fun consume(value: \(type)) {}\n"
    }

    // MARK: - BUG-143: forward references to later declarations

    // DEBT-SEMA-003: a top-level `val` initializer that reads its own symbol
    // (directly, e.g. via a call argument) is a use before initialization —
    // matching kotlinc's "variable must be initialized before use" diagnostic.

    // MARK: - TypeCheck: DEBT-SEMA-001 (forward-declared member property)

    // A member function that textually precedes a member property it
    // references only sees that property's header placeholder (`Any?`) on
    // typeCheckClassLikeMembers's first, source-order pass; the property's
    // real inferred type isn't known until its own PropertyDecl is checked
    // later in that same pass. A second, unconditional pass over every member
    // function re-checks each one after all properties are resolved, but
    // that recovers only the *type*, not the spurious KSWIFTK-TYPE-0001
    // already committed by the first pass. Diagnostics from that first,
    // speculative pass must be discarded so only the second, authoritative
    // pass's diagnostics are kept.

    // MARK: - Per-source diagnostic helpers

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
    }

    private func diagnosticsForPath(
        _ path: String,
        withCode code: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        diagnosticsForPath(path, in: ctx).filter { $0.code == code }
    }

    private func assertHasDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = diagnostics.contains { $0.code == code }
        #expect(found, "Expected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    private func assertNoDiagnostic(
        _ code: String,
        in diagnostics: [Diagnostic]
    ) {
        let found = !diagnostics.contains { $0.code == code }
        #expect(found, "Unexpected diagnostic \(code), got: \(diagnostics.map { $0.code })")
    }

    // MARK: - Path-aware expression search helpers

    private func firstExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func lastExprIDInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        var result: ExprID?
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { result = exprID }
        }
        return result
    }

    private func allExprIDsInPath(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func memberCallExprIDsInPath(
        named name: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, range) = expr,
                  interner.resolve(callee) == name,
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

    private func firstUserObjectLiteralDeclIDInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager
    ) -> DeclID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .objectLiteral(_, declID, _) = expr,
                  let declID,
                  let range = ast.arena.exprRange(exprID),
                  sourceManager.path(of: range.start.file) == path
            else { continue }
            return declID
        }
        return nil
    }

    private func findMainBodyStatementsInPath(
        in ast: ASTModule,
        path: String,
        sourceManager: SourceManager,
        interner: StringInterner
    ) -> [ExprID]? {
        guard let fileID = sourceManager.fileID(forPath: path) else { return nil }
        for file in ast.files {
            guard file.fileID == fileID else { continue }
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl,
                      interner.resolve(function.name) == "main",
                      case let .block(statements, _) = function.body
                else { continue }
                return statements
            }
        }
        return nil
    }

    // MARK: - Consolidated runSema clean tests

    @Test
    func testRunSemaClean() throws {

        let sources: [String] = [
            // testStarProjectionInTypeAnnotationDoesNotCrashCompiler
            """
            package sample0

                    class Container<T>(val item: T)
                    typealias OutContainer<T> = Container<out T>

                    fun readStar(c: Container<*>): Any? = c.item
                    fun eraseType(list: List<*>): Int = 0
                    fun expandAlias(c: OutContainer<*>): Container<*> = c
                    fun main(): Int = 0

            """,
            // testFunctionTypeParameterResolvesCorrectly
            """
            package sample1

                    fun apply(f: (Int) -> Int, x: Int): Int = f(x)
                    fun main() = apply(f = { it -> it + 1 }, x = 5)

            """,
            // testSecondaryConstructorDefinesSymbol
            """
            package sample2

                    class Person(val name: String) {
                        constructor(first: String, last: String): this(first)
                    }
                    fun main() = Person("Alice")

            """,
            // testEnumClassEntriesDefineFieldSymbols
            """
            package sample3

                    enum class Color { RED, GREEN, BLUE }
                    fun main(): Int = 0

            """,
            // testObjectDeclarationDefinesSymbol
            """
            package sample4

                    object Singleton {
                        val value: Int = 42
                    }
                    fun main(): Int = 0

            """,
            // testInterfaceDeclarationDefinesSymbol
            """
            package sample5

                    interface Greetable {
                        fun greet(): String
                    }
                    fun main(): Int = 0

            """,
            // testTypeAliasDeclarationDefinesSymbol
            """
            package sample6

                    typealias Name = String
                    fun greet(n: Name): String = n
                    fun main() = greet("World")

            """,
            // testExtensionFunctionHasReceiverType
            """
            package sample7

                    fun String.shout(): String = this
                    fun main() = "hello".shout()

            """,
            // testReifiedInlineFunctionDefinesTypeParameter
            """
            package sample8

                    inline fun <reified T> typeCheck(x: Any): Boolean = x is T
                    fun main() = typeCheck<Int>(42)

            """,
            // testClassMemberFunctionsAndPropertiesDefineSymbols
            """
            package sample9

                    class Counter {
                        val count: Int = 0
                        fun increment(): Int = count
                    }
                    fun main(): Int = 0

            """,
            // testFixedAndTrailingVarargOverloadsDoNotConflict
            """
            package sample10

                    fun choose(a: Int, b: Int): Int = a
                    fun choose(a: Int, vararg other: Int): Int = a
                    fun main(): Int = choose(1, 2, 3)

            """,
            // testClassThenSameNamedFunctionDoesNotConflict
            """
            package sample11

                    class Box(val value: Int)
                    fun Box(seed: Long): Box = Box(seed.toInt())
                    fun main(): Int = Box(1L).value

            """,
            // testFunctionThenSameNamedClassDoesNotConflict
            """
            package sample12

                    fun Box(seed: Long): Int = seed.toInt()
                    class Box(val value: Int)
                    fun main(): Int = 0

            """,
            // testCallResolutionMergesConstructorAndSameNamedFunctionCandidates
            """
            package sample13

                    class Box(val value: Int)
                    fun Box(seed: Long): Box = Box(seed.toInt() + 1000)
                    fun main(): Int {
                        val viaFunction = Box(5L)
                        val viaConstructor = Box(7)
                        return viaFunction.value + viaConstructor.value
                    }

            """,
            // testAbstractClassYieldsToCoexistingFactoryFunction
            """
            package sample14

                    abstract class Shape {
                        abstract fun area(): Double
                    }
                    class Circle(val radius: Double) : Shape() {
                        override fun area(): Double = radius * radius * 3.14159
                    }
                    fun Shape(radius: Double): Shape = Circle(radius)
                    fun main(): Double = Shape(2.0).area()

            """,
            // testSyntheticClassConstructorMatchingFactoryFunctionSignatureIsNotAmbiguous
            """
            package sample15

                    import kotlin.io.path.Path

                    fun makePath(raw: String): Path = Path(raw)

            """,
            // testTopLevelFunctionSignatureResolvesLaterDeclaredClass
            """
            package sample16

                    fun make(seed: Long): Box = Box(seed.toInt())
                    class Box(val value: Int)
                    fun main(): Int = make(3L).value

            """,
            // testTopLevelPropertyTypeResolvesLaterDeclaredClass
            """
            package sample17

                    val shared: Box = Box(1)
                    class Box(val value: Int)
                    fun main(): Int = shared.value

            """,
            // testMemberSignatureResolvesLaterDeclaredTopLevelType
            """
            package sample18

                    class Holder {
                        fun wrap(value: Int): Payload = Payload(value)
                        fun paint(): Shape = Circle
                    }
                    class Payload(val value: Int)
                    interface Shape
                    object Circle : Shape
                    fun main(): Int = Holder().wrap(2).value

            """,
            // testSignatureResolvesLaterDeclaredTypeAlias
            """
            package sample19

                    fun step(value: Meters): Meters = value + 1
                    typealias Meters = Int
                    fun main(): Int = step(1)

            """,
            // testNonSelfReferentialTopLevelInitializerStillCompiles
            """
            package sample20

                    val greeting: String = "hello"
                    val shout: String = greeting.uppercase()
                    fun main() {}

            """,
            // testForwardDeclaredMemberPropertyReferencedFromEarlierMemberFunctionTypeChecks
            """
            package sample21

                    class Forward {
                        fun get(): Int = value
                        var value = 10
                    }
                    fun main(): Int = Forward().get()

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testStarProjectionInTypeAnnotationDoesNotCrashCompiler ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0063", in: sample0Diagnostics)

            }

            // === testFunctionTypeParameterResolvesCorrectly ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let applySymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "apply"
                }
                #expect(applySymbol != nil)

            }

            // === testSecondaryConstructorDefinesSymbol ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let ctorSymbols = sema.symbols.allSymbols().filter { symbol in
                    symbol.kind == .constructor
                }
                #expect(ctorSymbols.count >= 2, "Expected primary + secondary constructor")

            }

            // === testEnumClassEntriesDefineFieldSymbols ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let fieldSymbols = sema.symbols.allSymbols().filter { symbol in
                    symbol.kind == .field && (
                        interner.resolve(symbol.name) == "RED" ||
                            interner.resolve(symbol.name) == "GREEN" ||
                            interner.resolve(symbol.name) == "BLUE"
                    )
                }
                #expect(fieldSymbols.count >= 1, "Expected at least 1 enum entry field")

            }

            // === testObjectDeclarationDefinesSymbol ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let objectSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "Singleton" && symbol.kind == .object
                }
                #expect(objectSymbol != nil)

            }

            // === testInterfaceDeclarationDefinesSymbol ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let interfaceSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "Greetable" && symbol.kind == .interface
                }
                #expect(interfaceSymbol != nil)

            }

            // === testTypeAliasDeclarationDefinesSymbol ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let aliasSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "Name" && symbol.kind == .typeAlias
                }
                #expect(aliasSymbol != nil)

            }

            // === testExtensionFunctionHasReceiverType ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let shoutSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "shout"
                }
                #expect(shoutSymbol != nil)
                if let sym = shoutSymbol,
                   let sig = sema.symbols.functionSignature(for: sym.id)
                {
                    #expect(sig.receiverType != nil)
                }

            }

            // === testReifiedInlineFunctionDefinesTypeParameter ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let typeCheckSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "typeCheck"
                }
                #expect(typeCheckSymbol != nil)
                if let sym = typeCheckSymbol,
                   let sig = sema.symbols.functionSignature(for: sym.id)
                {
                    let reifiedEmpty = sig.reifiedTypeParameterIndices.isEmpty
                    #expect(!reifiedEmpty)
                }

            }

            // === testClassMemberFunctionsAndPropertiesDefineSymbols ===

            do {

                let sample9Path = paths[9]

                let path = sample9Path

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let incrementSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "increment"
                }
                #expect(incrementSymbol != nil)
                let countSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "count" && symbol.kind == .property
                }
                #expect(countSymbol != nil)

            }

            // === testFixedAndTrailingVarargOverloadsDoNotConflict ===

            do {

                let sample10Path = paths[10]

                let path = sample10Path

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0001", in: sample10Diagnostics)

            }

            // === testClassThenSameNamedFunctionDoesNotConflict ===

            do {

                let sample11Path = paths[11]

                let path = sample11Path

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0001", in: sample11Diagnostics)

            }

            // === testFunctionThenSameNamedClassDoesNotConflict ===

            do {

                let sample12Path = paths[12]

                let path = sample12Path

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0001", in: sample12Diagnostics)

            }

            // === testCallResolutionMergesConstructorAndSameNamedFunctionCandidates ===

            do {

                let sample13Path = paths[13]

                let path = sample13Path

                let sample13Diagnostics = diagnosticsForPath(sample13Path, in: ctx)

                // Before the KSP-CAP-006 fix, the class's constructors were only
                // considered as call candidates when no top-level function of the
                // same name existed at all -- so once `fun Box(seed: Long)` was
                // found, `Box(Int)` constructor calls (including this one, made from
                // inside the function's own body) failed with
                // "No viable overload found for call" even though the argument type
                // unambiguously matched the constructor.
                    assertNoDiagnostic("KSWIFTK-SEMA-0001", in: sample13Diagnostics)
                    assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample13Diagnostics)

            }

            // === testAbstractClassYieldsToCoexistingFactoryFunction ===

            do {

                let sample14Path = paths[14]

                let path = sample14Path

                let sample14Diagnostics = diagnosticsForPath(sample14Path, in: ctx)

                // Mirrors the real kotlin.random.Random shape: an abstract class
                // whose only usable "constructor-like" call target is a coexisting
                // top-level factory function. The abstract-instantiation diagnostic
                // must not fire when the factory function is a viable candidate.
                    assertNoDiagnostic("KSWIFTK-SEMA-0001", in: sample14Diagnostics)
                    assertNoDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: sample14Diagnostics)
                    assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample14Diagnostics)

            }

            // === testSyntheticClassConstructorMatchingFactoryFunctionSignatureIsNotAmbiguous ===

            do {

                let sample15Path = paths[15]

                let path = sample15Path

                let sample15Diagnostics = diagnosticsForPath(sample15Path, in: ctx)

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
                    assertNoDiagnostic("KSWIFTK-SEMA-0001", in: sample15Diagnostics)
                    assertNoDiagnostic("KSWIFTK-SEMA-0002", in: sample15Diagnostics)
                    assertNoDiagnostic("KSWIFTK-SEMA-0023", in: sample15Diagnostics)

            }

            // === testTopLevelFunctionSignatureResolvesLaterDeclaredClass ===

            do {

                let sample16Path = paths[16]

                let path = sample16Path

                let sample16Diagnostics = diagnosticsForPath(sample16Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sample16Diagnostics)

            }

            // === testTopLevelPropertyTypeResolvesLaterDeclaredClass ===

            do {

                let sample17Path = paths[17]

                let path = sample17Path

                let sample17Diagnostics = diagnosticsForPath(sample17Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sample17Diagnostics)

            }

            // === testMemberSignatureResolvesLaterDeclaredTopLevelType ===

            do {

                let sample18Path = paths[18]

                let path = sample18Path

                let sample18Diagnostics = diagnosticsForPath(sample18Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0025", in: sample18Diagnostics)

            }

            // === testSignatureResolvesLaterDeclaredTypeAlias ===

            do {

                let sample19Path = paths[19]

                let path = sample19Path

                let sample19Diagnostics = diagnosticsForPath(sample19Path, in: ctx)

                // Type aliases are collected before the remaining headers, so the alias
                // resolves to its underlying type rather than to a bare alias symbol.
                    #expect(sample19Diagnostics.isEmpty, "Got: \(sample19Diagnostics)")

            }

            // === testNonSelfReferentialTopLevelInitializerStillCompiles ===

            do {

                let sample20Path = paths[20]

                let path = sample20Path

                let sample20Diagnostics = diagnosticsForPath(sample20Path, in: ctx)

                #expect(sample20Diagnostics.isEmpty, "Got: \(sample20Diagnostics)")

            }

            // === testForwardDeclaredMemberPropertyReferencedFromEarlierMemberFunctionTypeChecks ===

            do {

                let sample21Path = paths[21]

                let path = sample21Path

                let sample21Diagnostics = diagnosticsForPath(sample21Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-TYPE-0001", in: sample21Diagnostics)

            }

        }
    }

    // MARK: - Consolidated runSema error tests

    @Test
    func testRunSemaWithExpectedDiagnostics() throws {

        let sources: [String] = [
            // testDuplicateParameterNameEmitsDiagnostic
            """
            package sample0

                    fun bad(x: Int, x: Int): Int = x

            """,
            // testReifiedOnNonInlineFunctionEmitsDiagnostic
            """
            package sample1

                    fun <reified T> badReified(x: Any): Boolean = x is T
                    fun main(): Int = 0

            """,
            // testDuplicateTopLevelDeclarationEmitsDiagnostic
            """
            package sample2

                    val x: Int = 1
                    val x: Int = 2
                    fun main(): Int = 0

            """,
            // testDuplicateClassDeclarationStillConflicts
            """
            package sample3

                    class Box(val value: Int)
                    class Box(val other: Int)
                    fun main(): Int = 0

            """,
            // testAbstractClassInstantiationStillErrorsWithoutCoexistingFunction
            """
            package sample4

                    abstract class Shape {
                        abstract fun area(): Double
                    }
                    fun main() {
                        val s = Shape()
                    }

            """,
            // testGenuinelyUnknownTypeStillErrors
            """
            package sample5

                    fun make(): Missing = TODO()
                    fun main() {}

            """,
            // testSelfReferentialTopLevelInitializerIsDetected
            """
            package sample6

                    val cyclic: List<*> = listOf(cyclic)
                    fun main() {}

            """,
            // testMemberFunctionWithGenuinelyWrongReturnTypeStillErrorsAcrossPropertyForwardReference
            """
            package sample7

                    class Forward {
                        fun get(): String = value
                        var value = 10
                    }
                    fun main() {}

            """,
            // testForwardReferencedPropertyOwnInitializerMismatchStillErrors
            """
            package sample8

                    class Forward {
                        fun get(): Int = value
                        var value: Int = "oops"
                    }
                    fun main() {}

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testDuplicateParameterNameEmitsDiagnostic ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-TYPE-0002", in: sample0Diagnostics)

            }

            // === testReifiedOnNonInlineFunctionEmitsDiagnostic ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0020", in: sample1Diagnostics)

            }

            // === testDuplicateTopLevelDeclarationEmitsDiagnostic ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0001", in: sample2Diagnostics)

            }

            // === testDuplicateClassDeclarationStillConflicts ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                // Guards against over-loosening: two nominal types of the same name
                // (as opposed to a nominal type + a callable) must still conflict.
                    assertHasDiagnostic("KSWIFTK-SEMA-0001", in: sample3Diagnostics)

            }

            // === testAbstractClassInstantiationStillErrorsWithoutCoexistingFunction ===

            do {

                let sample4Path = paths[4]

                let path = sample4Path

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                // Guards against over-loosening the P5-112 abstract-instantiation
                // check: when no coexisting top-level function offers a viable
                // candidate, calling an abstract class's own name must still error.
                    assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: sample4Diagnostics)

            }

            // === testGenuinelyUnknownTypeStillErrors ===

            do {

                let sample5Path = paths[5]

                let _ = sample5Path

                // KSWIFTK-SEMA-0025 is emitted with a nil range, so path filtering
                // would hide it; check the full diagnostic list instead.
                let hasMissingTypeError = ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-0025" }
                #expect(hasMissingTypeError, "Expected KSWIFTK-SEMA-0025 for unresolved type Missing")

            }

            // === testSelfReferentialTopLevelInitializerIsDetected ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                assertHasDiagnostic("KSWIFTK-SEMA-0031", in: sample6Diagnostics)

            }

            // === testMemberFunctionWithGenuinelyWrongReturnTypeStillErrorsAcrossPropertyForwardReference ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                // Guards against over-loosening: discarding the first pass's
                // diagnostics must not hide a return-type mismatch that the second,
                // authoritative pass still finds once `value`'s real type (`Int`) is
                // known -- `get()` declares `String`, which `Int` never satisfies.
                    assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sample7Diagnostics)

            }

            // === testForwardReferencedPropertyOwnInitializerMismatchStillErrors ===

            do {

                let sample8Path = paths[8]

                let path = sample8Path

                let source = sources[8]

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                // Guards against over-truncation: only the speculative member
                // *function* pass's diagnostics are discarded. A member property's
                // own initializer type mismatch is checked once, in source order,
                // and must still be reported even though it textually follows a
                // function that refers to it.
                    assertHasDiagnostic("KSWIFTK-TYPE-0001", in: sample8Diagnostics)

            }

        }
    }

    // MARK: - Consolidated runToKIR clean tests

    @Test
    func testRunToKIRClean() throws {

        let sources: [String] = [
            // testExpressionBodyFunctionBindsReturnType
            """
            package sample0

                    fun answer(): Int = 42
                    fun main() = answer()

            """,
            // testPropertyDeclBindsIdentifierAndType
            """
            package sample1

                    val greeting: String = "hello"
                    fun main() = greeting

            """,
            // testNullableTypeAnnotationResolvesCorrectly
            """
            package sample2

                    fun nullable(x: Int?): Int? = x
                    fun main() = nullable(null)

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)

            try runToKIR(ctx)

            let module = try #require(ctx.kir)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testExpressionBodyFunctionBindsReturnType ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let exprTypesEmpty = sema.bindings.exprTypes.isEmpty
                #expect(!exprTypesEmpty)

            }

            // === testPropertyDeclBindsIdentifierAndType ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let greetingSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "greeting"
                }
                #expect(greetingSymbol != nil)

            }

            // === testNullableTypeAnnotationResolvesCorrectly ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let nullableSymbol = sema.symbols.allSymbols().first { symbol in
                    interner.resolve(symbol.name) == "nullable"
                }
                #expect(nullableSymbol != nil)
                if let sym = nullableSymbol,
                   let sig = sema.symbols.functionSignature(for: sym.id)
                {
                    #expect(sig.parameterTypes.count == 1)
                }

            }

        }
    }

}

#endif
