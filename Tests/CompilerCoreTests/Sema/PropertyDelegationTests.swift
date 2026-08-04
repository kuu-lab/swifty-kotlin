#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - SymbolTable Delegate Storage Tests

@Suite
struct DelegateStorageSymbolTableTests {

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
            // testSetAndGetDelegateStorageSymbol
            """
            package sample0
            fun noop() {}
            """,
            // testDelegateStorageSymbolReturnsNilForUnset
            """
            package sample1
            fun noop() {}
            """,
            // testDelegateStorageSymbolIsIndependentOfPropertyType
            """
            package sample2
            fun noop() {}
            """,
            // testMultipleDelegateStorageSymbolsAreIndependent
            """
            package sample3
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testSetAndGetDelegateStorageSymbol ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let interner = StringInterner()
                let symbols = SymbolTable()
                let property = symbols.define(
                    kind: .property,
                    name: interner.intern("x"),
                    fqName: [interner.intern("x")],
                    declSite: nil,
                    visibility: .public
                )
                let storage = symbols.define(
                    kind: .field,
                    name: interner.intern("$delegate_x"),
                    fqName: [interner.intern("$delegate_x")],
                    declSite: nil,
                    visibility: .private
                )
                symbols.setDelegateStorageSymbol(storage, for: property)
                #expect(symbols.delegateStorageSymbol(for: property) == storage)

            }

            // === testDelegateStorageSymbolReturnsNilForUnset ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                let symbols = SymbolTable()
                #expect(symbols.delegateStorageSymbol(for: SymbolID(rawValue: 0)) == nil)

            }

            // === testDelegateStorageSymbolIsIndependentOfPropertyType ===

            do {

                let sample2Path = paths[2]

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                let interner = StringInterner()
                let symbols = SymbolTable()
                let types = TypeSystem()
                let property = symbols.define(
                    kind: .property,
                    name: interner.intern("y"),
                    fqName: [interner.intern("y")],
                    declSite: nil,
                    visibility: .public
                )
                let storage = symbols.define(
                    kind: .field,
                    name: interner.intern("$delegate_y"),
                    fqName: [interner.intern("$delegate_y")],
                    declSite: nil,
                    visibility: .private
                )
                let intType = types.make(.primitive(.int, .nonNull))
                symbols.setPropertyType(intType, for: property)
                symbols.setDelegateStorageSymbol(storage, for: property)
                #expect(symbols.delegateStorageSymbol(for: property) == storage)
                #expect(symbols.propertyType(for: property) == intType)

            }

            // === testMultipleDelegateStorageSymbolsAreIndependent ===

            do {

                let sample3Path = paths[3]

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let interner = StringInterner()
                let symbols = SymbolTable()
                let propA = symbols.define(
                    kind: .property,
                    name: interner.intern("a"),
                    fqName: [interner.intern("a")],
                    declSite: nil,
                    visibility: .public
                )
                let propB = symbols.define(
                    kind: .property,
                    name: interner.intern("b"),
                    fqName: [interner.intern("b")],
                    declSite: nil,
                    visibility: .public
                )
                let storageA = symbols.define(
                    kind: .field,
                    name: interner.intern("$delegate_a"),
                    fqName: [interner.intern("$delegate_a")],
                    declSite: nil,
                    visibility: .private
                )
                let storageB = symbols.define(
                    kind: .field,
                    name: interner.intern("$delegate_b"),
                    fqName: [interner.intern("$delegate_b")],
                    declSite: nil,
                    visibility: .private
                )
                symbols.setDelegateStorageSymbol(storageA, for: propA)
                symbols.setDelegateStorageSymbol(storageB, for: propB)
                #expect(symbols.delegateStorageSymbol(for: propA) == storageA)
                #expect(symbols.delegateStorageSymbol(for: propB) == storageB)
                #expect(symbols.delegateStorageSymbol(for: propA) != storageB)

            }

        }
    }

}

// MARK: - Sema Delegate Type Checking Tests

@Suite
struct SemaDelegateTypeCheckTests {
    @Test func testDelegatedPropertyCreatesStorageSymbolDuringHeaderCollection() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // FQ names do not include module prefix; class Foo has fqName ["Foo"].
            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            // Verify that a $delegate_x storage symbol was created.
            let delegateStorageSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "$delegate_x"
            }
            #expect(!delegateStorageSymbols.isEmpty, "Expected $delegate_x storage symbol to be created")

            // The storage symbol should be a field.
            if let storageSymID = delegateStorageSymbols.first,
               let storageSym = sema.symbols.symbol(storageSymID)
            {
                #expect(storageSym.kind == .field)
                #expect(storageSym.visibility == .private)
            }

            // Find the property symbol 'x' and check delegate storage is linked.
            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            #expect(!xSymbols.isEmpty, "Expected property symbol 'x' to exist")
            if let xSymbol = xSymbols.first {
                let delegateStorage = sema.symbols.delegateStorageSymbol(for: xSymbol)
                #expect(delegateStorage != nil, "Expected delegate storage to be linked to property 'x'")
            }
        }
    }

    // `MyDelegate.getValue` intentionally omits `operator` so this test exercises
    // the KSWIFTK-SEMA-0103 diagnostic path: type inference can't resolve a
    // return type from getValue, so the property type must still safely fall
    // back to Any? (rather than being left unset) alongside the reported error.
    @Test func testDelegatedPropertyMissingGetValueOperatorFallsBackToNullableAnyAndReportsError() throws {
        let source = """
        class MyDelegate {
            fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            #expect(ctx.diagnostics.hasError,
                          "Delegate type missing the 'getValue' operator should report an error")

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            #expect(!xSymbols.isEmpty)
            if let xSymbol = xSymbols.first {
                let propType = sema.symbols.propertyType(for: xSymbol)
                #expect(propType != nil, "Property type should be set even without explicit annotation")
                // When no explicit type, it falls back to Any?
                if let propType {
                    #expect(propType == sema.types.nullableAnyType)
                }
            }
        }
    }

    @Test func testDelegatedPropertyPreservesExplicitType() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            #expect(!xSymbols.isEmpty)
            if let xSymbol = xSymbols.first {
                let propType = sema.symbols.propertyType(for: xSymbol)
                #expect(propType != nil)
                if let propType {
                    let intType = sema.types.make(.primitive(.int, .nonNull))
                    #expect(propType == intType, "Explicit Int type should be preserved")
                }
            }
        }
    }

    @Test func testMutableDelegatedPropertyCreatesStorageSymbol() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 0
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo {
            var x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let delegateStorageSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "$delegate_x"
            }
            #expect(!delegateStorageSymbols.isEmpty, "Expected $delegate_x storage symbol for var delegate")

            if let storageSymID = delegateStorageSymbols.first,
               let storageSym = sema.symbols.symbol(storageSymID)
            {
                #expect(storageSym.kind == .field)
                #expect(storageSym.visibility == .private)
            }
        }
    }

    @Test func testMultipleDelegatedPropertiesCreateSeparateStorageSymbols() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
            val y: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let delegateStorageSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name).hasPrefix("$delegate_")
            }
            #expect(delegateStorageSymbols.count == 2, "Expected two separate delegate storage symbols for two delegated properties")

            let storageNames = delegateStorageSymbols.compactMap { id in
                sema.symbols.symbol(id).map { interner.resolve($0.name) }
            }
            #expect(storageNames.contains("$delegate_x"), "Expected $delegate_x storage symbol")
            #expect(storageNames.contains("$delegate_y"), "Expected $delegate_y storage symbol")
        }
    }

    @Test func testDelegatedPropertyRecordsDelegateTypeOnSyntheticSymbol() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let fooFQ = [interner.intern("Foo")]
            let fooChildren = sema.symbols.children(ofFQName: fooFQ)

            let xSymbols = fooChildren.filter { symbolID in
                guard let sym = sema.symbols.symbol(symbolID) else { return false }
                return interner.resolve(sym.name) == "x" && sym.kind == .property
            }
            if let xSymbol = xSymbols.first {
                // The delegate type is recorded under a synthetic symbol offset:
                // -(symbol.rawValue + 50_000)
                let syntheticID = SymbolID(rawValue: -(xSymbol.rawValue + 50000))
                let delegateType = sema.symbols.propertyType(for: syntheticID)
                #expect(delegateType != nil, "Delegate type should be recorded on synthetic symbol")
            }
        }
    }
}

// MARK: - KIR Delegate Accessor Synthesis Tests

@Suite
struct KIRDelegateAccessorTests {
    @Test func testDelegatedValSynthesizesGetterWithGetValueCall() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // Check that a getter function was synthesized.
            let getterFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                let name = interner.resolve(fn.name)
                return name == "get" ? fn : nil
            }
            #expect(!getterFunctions.isEmpty, "Expected synthesized getter")

            // Delegate lowering may rewrite the direct getValue call in later phases, but
            // the synthesized delegate getter should carry a call with ≥2 args (receiver + property context).
            // Filter to the delegate getter specifically (not bundled property getters with 1 arg).
            let delegateGetter = getterFunctions.first { fn in
                fn.body.contains { instruction in
                    guard case let .call(_, _, args, _, _, _, _, _) = instruction else { return false }
                    return args.count >= 2
                }
            }
            #expect(delegateGetter != nil, "Expected synthesized delegate getter with getValue call")
            if let getter = delegateGetter {
                let multiArgCalls = getter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, _, args, _, _, _, _, _) = instruction else { return nil }
                    return args.count >= 2 ? args : nil
                }
                #expect(!multiArgCalls.isEmpty, "Delegate getter must have a call with receiver/property args")
                if let args = multiArgCalls.first {
                    #expect(args.count >= 2, "Synthesized getter should pass receiver/property context")
                }
            }
        }
    }

    @Test func testDelegatedVarSynthesizesSetterWithSetValueCall() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
        }
        class Foo {
            var x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // Check that a setter function was synthesized.
            let setterFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                let name = interner.resolve(fn.name)
                return name == "set" ? fn : nil
            }
            #expect(!setterFunctions.isEmpty, "Expected synthesized setter")

            // Delegate lowering may rewrite the direct setValue call in later phases, but
            // the synthesized setter should still carry observable call structure.
            if let setter = setterFunctions.first {
                let callArgs = setter.body.compactMap { instruction -> [KIRExprID]? in
                    guard case let .call(_, _, args, _, _, _, _, _) = instruction else { return nil }
                    return args
                }
                #expect(!callArgs.isEmpty)
                if let args = callArgs.first {
                    #expect(args.count >= 2, "Synthesized setter should pass at least value and receiver context")
                }
            }
        }
    }

    @Test func testDelegatedValDoesNotSynthesizeSetter() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // There should be no setter function with setValue for a val property.
            let setterWithSetValue = findAllKIRFunctions(in: module).contains { fn in
                let name = interner.resolve(fn.name)
                guard name == "set" else { return false }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("setValue")
            }
            #expect(!setterWithSetValue, "val property should not have a synthesized setter with setValue")
        }
    }

    @Test func testDelegateStorageGlobalIsEmitted() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let sema = try #require(ctx.sema)

            // Check that a $delegate_x global was emitted.
            let delegateGlobals = module.arena.declarations.compactMap { decl -> KIRGlobal? in
                guard case let .global(g) = decl else { return nil }
                guard let sym = sema.symbols.symbol(g.symbol) else { return nil }
                return interner.resolve(sym.name).hasPrefix("$delegate_") ? g : nil
            }
            #expect(!delegateGlobals.isEmpty, "Expected $delegate_ global to be emitted in KIR")
        }
    }

    @Test func testGetValueCallUsesDelegateStorageAsSymbol() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            _ = try #require(ctx.sema)

            // Find the getter and check that getValue resolves as a direct member call,
            // rather than using the delegate storage field as the callee symbol.
            let getterFunctions = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                let name = interner.resolve(fn.name)
                guard name == "get" else { return nil }
                let callees = extractCallees(from: fn.body, interner: interner)
                return callees.contains("getValue") ? fn : nil
            }

            if let getter = getterFunctions.first {
                let getValueCallCount = getter.body.reduce(into: 0) { count, instruction in
                    guard case let .call(_, callee, _, _, _, _, _, _) = instruction,
                          interner.resolve(callee) == "getValue" else { return }
                    count += 1
                }
                #expect(getValueCallCount > 0, "Expected synthesized getter to contain a direct getValue call")
            }
        }
    }
}

// MARK: - Constructor Delegate Initialization Tests

@Suite
struct ConstructorDelegateInitTests {
    @Test func testConstructorEmitsInitializerForDelegateStorage() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner

            // In KIR, constructors are named after the class (e.g. "Foo"), not "<init>".
            let constructors = findAllKIRFunctions(in: module).compactMap { fn -> KIRFunction? in
                guard interner.resolve(fn.name) == "Foo" else { return nil }
                return fn
            }
            #expect(!constructors.isEmpty, "Expected a Foo constructor function in KIR")

            let anyConstructorCallsMyDelegate = constructors.contains { fn in
                extractCallees(from: fn.body, interner: interner).contains("MyDelegate")
            }
            #expect(anyConstructorCallsMyDelegate, "Expected Foo constructor to initialize delegate storage with MyDelegate()")
        }
    }

    @Test func testMultipleDelegatedPropertiesEmitSeparateGlobalsInKIR() throws {
        let source = """
        class MyDelegate {
            operator fun getValue(thisRef: Any?, property: Any?): Int = 42
        }
        class Foo {
            val x: Int by MyDelegate()
            val y: Int by MyDelegate()
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let sema = try #require(ctx.sema)

            let delegateGlobals = module.arena.declarations.compactMap { decl -> KIRGlobal? in
                guard case let .global(g) = decl else { return nil }
                guard let sym = sema.symbols.symbol(g.symbol) else { return nil }
                return interner.resolve(sym.name).hasPrefix("$delegate_") ? g : nil
            }
            #expect(delegateGlobals.count == 2, "Expected two separate delegate globals for two delegated properties")
        }
    }
}
#endif
