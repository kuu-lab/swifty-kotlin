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

    private func classChildren(
        package: String,
        className: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let fq = [interner.intern(package), interner.intern(className)]
        return sema.symbols.children(ofFQName: fq)
    }

    private func childSymbol(
        named name: String,
        kind: SymbolKind,
        package: String,
        className: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        classChildren(package: package, className: className, sema: sema, interner: interner).first { symbolID in
            guard let sym = sema.symbols.symbol(symbolID) else { return false }
            return interner.resolve(sym.name) == name && sym.kind == kind
        }
    }

    private func delegateStorageSymbol(
        for propertyName: String,
        package: String,
        className: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        childSymbol(
            named: "$delegate_\(propertyName)",
            kind: .field,
            package: package,
            className: className,
            sema: sema,
            interner: interner
        )
    }

    @Test func testDelegateSema() throws {
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
            """
            package sample4

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }

            class Foo {
                val x: Int by MyDelegate()
            }
            """,
            """
            package sample5

            class MyDelegate {
                fun getValue(thisRef: Any?, property: Any?): Int = 42
            }

            class Foo {
                val x by MyDelegate()
            }
            """,
            """
            package sample6

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }

            class Foo {
                val x: Int by MyDelegate()
            }
            """,
            """
            package sample7

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 0
                operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
            }

            class Foo {
                var x: Int by MyDelegate()
            }
            """,
            """
            package sample8

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }

            class Foo {
                val x: Int by MyDelegate()
                val y: Int by MyDelegate()
            }
            """,
            """
            package sample9

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }

            class Foo {
                val x: Int by MyDelegate()
            }
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
            // sample4: storage symbol exists and is linked to property 'x'.
            do {
                let sample4Path = paths[4]
                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)
                #expect(
                    !sample4Diagnostics.contains { $0.severity == .error },
                    "sample4 should be clean, got: \(sample4Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
                )

                let xSymbol = try #require(
                    childSymbol(named: "x", kind: .property, package: "sample4", className: "Foo", sema: sema, interner: interner),
                    "Missing property symbol 'x' in sample4"
                )
                let storage = try #require(
                    delegateStorageSymbol(for: "x", package: "sample4", className: "Foo", sema: sema, interner: interner),
                    "Missing $delegate_x storage symbol in sample4"
                )

                if let storageSym = sema.symbols.symbol(storage) {
                    #expect(storageSym.kind == .field)
                    #expect(storageSym.visibility == .private)
                }

                #expect(
                    sema.symbols.delegateStorageSymbol(for: xSymbol) == storage,
                    "Expected delegate storage to be linked to property 'x' in sample4"
                )
            }

            // sample5: missing getValue operator reports error; property type falls back to Any?.
            do {
                let sample5Path = paths[5]
                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)
                #expect(
                    sample5Diagnostics.contains { $0.severity == .error },
                    "Delegate type missing the 'getValue' operator should report an error"
                )

                let xSymbol = try #require(
                    childSymbol(named: "x", kind: .property, package: "sample5", className: "Foo", sema: sema, interner: interner),
                    "Missing property symbol 'x' in sample5"
                )
                let propType = sema.symbols.propertyType(for: xSymbol)
                #expect(propType != nil, "Property type should be set even without explicit annotation")
                if let propType {
                    #expect(
                        propType == sema.types.nullableAnyType,
                        "Expected fallback Any? for property without explicit type, got \(propType)"
                    )
                }
            }

            // sample6: explicit Int type is preserved.
            do {
                let sample6Path = paths[6]
                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)
                #expect(
                    !sample6Diagnostics.contains { $0.severity == .error },
                    "sample6 should be clean, got: \(sample6Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
                )

                let xSymbol = try #require(
                    childSymbol(named: "x", kind: .property, package: "sample6", className: "Foo", sema: sema, interner: interner),
                    "Missing property symbol 'x' in sample6"
                )
                let propType = sema.symbols.propertyType(for: xSymbol)
                #expect(propType != nil)
                if let propType {
                    let intType = sema.types.make(.primitive(.int, .nonNull))
                    #expect(
                        propType == intType,
                        "Explicit Int type should be preserved, got \(propType)"
                    )
                }
            }

            // sample7: var delegate creates $delegate_x storage field.
            do {
                let sample7Path = paths[7]
                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)
                #expect(
                    !sample7Diagnostics.contains { $0.severity == .error },
                    "sample7 should be clean, got: \(sample7Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
                )

                let storage = try #require(
                    delegateStorageSymbol(for: "x", package: "sample7", className: "Foo", sema: sema, interner: interner),
                    "Missing $delegate_x storage symbol for var delegate in sample7"
                )

                if let storageSym = sema.symbols.symbol(storage) {
                    #expect(storageSym.kind == .field)
                    #expect(storageSym.visibility == .private)
                }
            }

            // sample8: multiple delegated properties create separate storage symbols.
            do {
                let sample8Path = paths[8]
                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)
                #expect(
                    !sample8Diagnostics.contains { $0.severity == .error },
                    "sample8 should be clean, got: \(sample8Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
                )

                let fooChildren = classChildren(package: "sample8", className: "Foo", sema: sema, interner: interner)
                let delegateStorageSymbols = fooChildren.filter { symbolID in
                    guard let sym = sema.symbols.symbol(symbolID) else { return false }
                    return interner.resolve(sym.name).hasPrefix("$delegate_")
                }
                #expect(
                    delegateStorageSymbols.count == 2,
                    "Expected two separate delegate storage symbols in sample8, got \(delegateStorageSymbols.count)"
                )

                let storageNames = delegateStorageSymbols.compactMap { id in
                    sema.symbols.symbol(id).map { interner.resolve($0.name) }
                }
                #expect(storageNames.contains("$delegate_x"))
                #expect(storageNames.contains("$delegate_y"))
            }

            // sample9: delegate type is recorded on a synthetic symbol offset.
            do {
                let sample9Path = paths[9]
                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)
                #expect(
                    !sample9Diagnostics.contains { $0.severity == .error },
                    "sample9 should be clean, got: \(sample9Diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | "))"
                )

                let xSymbol = try #require(
                    childSymbol(named: "x", kind: .property, package: "sample9", className: "Foo", sema: sema, interner: interner),
                    "Missing property symbol 'x' in sample9"
                )
                let syntheticID = SymbolID(rawValue: -(xSymbol.rawValue + 50000))
                let delegateType = sema.symbols.propertyType(for: syntheticID)
                #expect(delegateType != nil, "Delegate type should be recorded on synthetic symbol")
            }

        }
    }

}

// MARK: - KIR Delegate Lowering Tests

@Suite
struct KIRDelegateLoweringTests {
    private func fileID(for path: String, ctx: CompilationContext) -> FileID? {
        ctx.sourceManager.fileID(forPath: path)
    }

    private func decls(in module: KIRModule, fileID: FileID) -> [KIRDecl] {
        module.files
            .filter { $0.fileID == fileID }
            .flatMap { $0.decls }
            .compactMap { module.arena.decl($0) }
    }

    private func kirFunctions(
        in module: KIRModule,
        interner: StringInterner,
        fileID: FileID,
        name: String
    ) -> [KIRFunction] {
        decls(in: module, fileID: fileID).compactMap { decl -> KIRFunction? in
            guard case let .function(fn) = decl else { return nil }
            return interner.resolve(fn.name) == name ? fn : nil
        }
    }

    private func kirDelegateGlobals(
        in module: KIRModule,
        sema: SemaModule,
        interner: StringInterner,
        fileID: FileID
    ) -> [KIRGlobal] {
        decls(in: module, fileID: fileID).compactMap { decl -> KIRGlobal? in
            guard case let .global(g) = decl else { return nil }
            guard let sym = sema.symbols.symbol(g.symbol) else { return nil }
            return interner.resolve(sym.name).hasPrefix("$delegate_") ? g : nil
        }
    }

    @Test func testDelegateLowering() throws {
        let sources: [String] = [
            """
            package sample0

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }

            class FooVal {
                val x: Int by MyDelegate()
            }
            """,
            """
            package sample1

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
                operator fun setValue(thisRef: Any?, property: Any?, value: Int) {}
            }

            class FooVar {
                var x: Int by MyDelegate()
            }
            """,
            """
            package sample2

            class MyDelegate {
                operator fun getValue(thisRef: Any?, property: Any?): Int = 42
            }

            class FooMulti {
                val x: Int by MyDelegate()
                val y: Int by MyDelegate()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, emit: .kirDump)
            try runToKIR(ctx)

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let sample0FileID = try #require(fileID(for: paths[0], ctx: ctx), "Missing fileID for sample0")
            let sample1FileID = try #require(fileID(for: paths[1], ctx: ctx), "Missing fileID for sample1")
            let sample2FileID = try #require(fileID(for: paths[2], ctx: ctx), "Missing fileID for sample2")

            // sample0 (FooVal): synthesized getter contains a getValue call.
            do {
                let getters = kirFunctions(in: module, interner: interner, fileID: sample0FileID, name: "get")
                #expect(!getters.isEmpty, "Expected synthesized getter for FooVal")

                let delegateGetter = getters.first { fn in
                    fn.body.contains { instruction in
                        guard case let .call(_, _, args, _, _, _, _, _) = instruction else { return false }
                        return args.count >= 2
                    }
                }
                #expect(delegateGetter != nil, "Expected delegate getter with receiver/property args")

                if let getter = delegateGetter {
                    let getValueCallCount = getter.body.reduce(into: 0) { count, instruction in
                        guard case let .call(_, callee, _, _, _, _, _, _) = instruction,
                              interner.resolve(callee) == "getValue" else { return }
                        count += 1
                    }
                    #expect(getValueCallCount > 0, "Expected getter to contain a direct getValue call")
                }
            }

            // sample0 (FooVal): no setter function should carry a setValue call.
            do {
                let setters = kirFunctions(in: module, interner: interner, fileID: sample0FileID, name: "set")
                let setterWithSetValue = setters.contains { fn in
                    extractCallees(from: fn.body, interner: interner).contains("setValue")
                }
                #expect(!setterWithSetValue, "val property FooVal should not synthesize a setter with setValue")
            }

            // sample0 (FooVal): a $delegate_x global is emitted.
            do {
                let delegateGlobals = kirDelegateGlobals(in: module, sema: sema, interner: interner, fileID: sample0FileID)
                #expect(!delegateGlobals.isEmpty, "Expected $delegate_ global for FooVal")
            }

            // sample0 (FooVal): constructor initializes delegate storage with MyDelegate().
            do {
                let constructors = kirFunctions(in: module, interner: interner, fileID: sample0FileID, name: "FooVal")
                #expect(!constructors.isEmpty, "Expected a FooVal constructor in KIR")

                let anyConstructorCallsMyDelegate = constructors.contains { fn in
                    extractCallees(from: fn.body, interner: interner).contains("MyDelegate")
                }
                #expect(
                    anyConstructorCallsMyDelegate,
                    "Expected FooVal constructor to initialize delegate storage with MyDelegate()"
                )
            }

            // sample1 (FooVar): synthesized setter contains a setValue call.
            do {
                let setters = kirFunctions(in: module, interner: interner, fileID: sample1FileID, name: "set")
                #expect(!setters.isEmpty, "Expected synthesized setter for FooVar")

                let setterWithSetValue = setters.contains { fn in
                    extractCallees(from: fn.body, interner: interner).contains("setValue")
                }
                #expect(setterWithSetValue, "Expected FooVar setter to contain a setValue call")
            }

            // sample2 (FooMulti): two separate delegate globals are emitted.
            do {
                let delegateGlobals = kirDelegateGlobals(in: module, sema: sema, interner: interner, fileID: sample2FileID)
                #expect(
                    delegateGlobals.count == 2,
                    "Expected two separate delegate globals for FooMulti, got \(delegateGlobals.count)"
                )
            }
        }
    }
}

#endif
