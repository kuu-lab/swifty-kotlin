@testable import CompilerCore
import Foundation
import Testing

@Suite
struct VisibilityAccessControlTests {

    private func defineSymbol(
        _ symbols: SymbolTable,
        interner: StringInterner,
        kind: SymbolKind,
        name: String,
        visibility: Visibility,
        file: FileID = FileID(rawValue: 0)
    ) -> SymbolID {
        let interned = interner.intern(name)
        return symbols.define(
            kind: kind,
            name: interned,
            fqName: [interned],
            declSite: makeRange(file: file),
            visibility: visibility,
            flags: []
        )
    }

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
            // testPublicFunctionAccessibleWithinSameFile
            """
            package sample0

                    package test
                    public fun greet(): Int = 1
                    fun main(): Int = greet()

            """,
            // testInternalFunctionAccessibleWithinSameFile
            """
            package sample1

                    package test
                    internal fun helper(): Int = 1
                    fun main(): Int = helper()

            """,
            // testPrivateFunctionAccessibleWithinSameFile
            """
            package sample2

                    package test
                    private fun secret(): Int = 42
                    fun main(): Int = secret()

            """,
            // testPrivatePropertyAccessibleWithinSameFile
            """
            package sample3

                    package test
                    private val secretVal: Int = 99
                    fun main(): Int = secretVal

            """,
            // testVisibilityCheckerPublicAlwaysAccessible
            """
            package sample4
            fun noop() {}
            """,
            // testVisibilityCheckerInternalAlwaysAccessible
            """
            package sample5
            fun noop() {}
            """,
            // testVisibilityCheckerPrivateSameFile
            """
            package sample6
            fun noop() {}
            """,
            // testVisibilityCheckerPrivateDifferentFile
            """
            package sample7
            fun noop() {}
            """,
            // testVisibilityCheckerProtectedInSameClass
            """
            package sample8
            fun noop() {}
            """,
            // testVisibilityCheckerProtectedOutsideClass
            """
            package sample9
            fun noop() {}
            """,
            // testVisibilityCheckerProtectedInSubclass
            """
            package sample10
            fun noop() {}
            """,
            // testVisibilityCheckerPrivateMemberInSameClass
            """
            package sample11
            fun noop() {}
            """,
            // testVisibilityCheckerPrivateMemberOutsideClass
            """
            package sample12
            fun noop() {}
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testPublicFunctionAccessibleWithinSameFile ===

            do {

                let sample0Path = paths[0]

                let path = sample0Path

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0040", in: sample0Diagnostics)
                assertNoDiagnostic("KSWIFTK-SEMA-0041", in: sample0Diagnostics)

            }

            // === testInternalFunctionAccessibleWithinSameFile ===

            do {

                let sample1Path = paths[1]

                let path = sample1Path

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0040", in: sample1Diagnostics)

            }

            // === testPrivateFunctionAccessibleWithinSameFile ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0040", in: sample2Diagnostics)

            }

            // === testPrivatePropertyAccessibleWithinSameFile ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                assertNoDiagnostic("KSWIFTK-SEMA-0040", in: sample3Diagnostics)

            }

            // === testVisibilityCheckerPublicAlwaysAccessible ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "pubFn", visibility: .public)
                let symbol = try #require(symbols.symbol(sym))
                #expect(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil))

            }

            // === testVisibilityCheckerInternalAlwaysAccessible ===

            do {

                let sample5Path = paths[5]

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "intFn", visibility: .internal)
                let symbol = try #require(symbols.symbol(sym))
                #expect(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil))

            }

            // === testVisibilityCheckerPrivateSameFile ===

            do {

                let sample6Path = paths[6]

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "privFn", visibility: .private, file: FileID(rawValue: 0))
                let symbol = try #require(symbols.symbol(sym))
                #expect(checker.isAccessible(symbol, fromFile: FileID(rawValue: 0), enclosingClass: nil))

            }

            // === testVisibilityCheckerPrivateDifferentFile ===

            do {

                let sample7Path = paths[7]

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let sym = defineSymbol(symbols, interner: interner, kind: .function, name: "privFn2", visibility: .private, file: FileID(rawValue: 0))
                let symbol = try #require(symbols.symbol(sym))
                #expect(!(checker.isAccessible(symbol, fromFile: FileID(rawValue: 1), enclosingClass: nil)))

            }

            // === testVisibilityCheckerProtectedInSameClass ===

            do {

                let sample8Path = paths[8]

                let sample8Diagnostics = diagnosticsForPath(sample8Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "MyClass", visibility: .public)
                let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protMethod", visibility: .protected)
                symbols.setParentSymbol(classSym, for: memberSym)
                let member = try #require(symbols.symbol(memberSym))
                #expect(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: classSym))

            }

            // === testVisibilityCheckerProtectedOutsideClass ===

            do {

                let sample9Path = paths[9]

                let sample9Diagnostics = diagnosticsForPath(sample9Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "MyClass2", visibility: .public)
                let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protMethod2", visibility: .protected)
                symbols.setParentSymbol(classSym, for: memberSym)
                let member = try #require(symbols.symbol(memberSym))
                #expect(!(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: nil)))

            }

            // === testVisibilityCheckerProtectedInSubclass ===

            do {

                let sample10Path = paths[10]

                let sample10Diagnostics = diagnosticsForPath(sample10Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let baseSym = defineSymbol(symbols, interner: interner, kind: .class, name: "Base", visibility: .public)
                let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "protSubMethod", visibility: .protected)
                symbols.setParentSymbol(baseSym, for: memberSym)
                let childSym = defineSymbol(symbols, interner: interner, kind: .class, name: "Child", visibility: .public)
                symbols.setDirectSupertypes([baseSym], for: childSym)
                let member = try #require(symbols.symbol(memberSym))
                #expect(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: childSym))

            }

            // === testVisibilityCheckerPrivateMemberInSameClass ===

            do {

                let sample11Path = paths[11]

                let sample11Diagnostics = diagnosticsForPath(sample11Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "PrivClass", visibility: .public)
                let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "privMethod", visibility: .private)
                symbols.setParentSymbol(classSym, for: memberSym)
                let member = try #require(symbols.symbol(memberSym))
                #expect(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: classSym))

            }

            // === testVisibilityCheckerPrivateMemberOutsideClass ===

            do {

                let sample12Path = paths[12]

                let sample12Diagnostics = diagnosticsForPath(sample12Path, in: ctx)

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let classSym = defineSymbol(symbols, interner: interner, kind: .class, name: "OwnerClass", visibility: .public)
                let otherClassSym = defineSymbol(symbols, interner: interner, kind: .class, name: "OtherClass", visibility: .public)
                let memberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "privMethod2", visibility: .private)
                symbols.setParentSymbol(classSym, for: memberSym)
                let member = try #require(symbols.symbol(memberSym))
                #expect(!(checker.isAccessible(member, fromFile: FileID(rawValue: 0), enclosingClass: otherClassSym)))

            }

            // === testVisibilityCheckerSharedEnclosingClassPrivateAccess ===

            do {

                let (_, symbols, _, interner) = makeSemaModule()
                let checker = VisibilityChecker(symbols: symbols)
                let outerClassSym = defineSymbol(symbols, interner: interner, kind: .class, name: "OuterClass", visibility: .public)
                let nestedASym = defineSymbol(symbols, interner: interner, kind: .class, name: "NestedA", visibility: .private)
                symbols.setParentSymbol(outerClassSym, for: nestedASym)
                let nestedBSym = defineSymbol(symbols, interner: interner, kind: .class, name: "NestedB", visibility: .public)
                symbols.setParentSymbol(outerClassSym, for: nestedBSym)

                let nestedAMemberSym = defineSymbol(symbols, interner: interner, kind: .function, name: "privA", visibility: .private)
                symbols.setParentSymbol(nestedASym, for: nestedAMemberSym)
                let nestedAMember = try #require(symbols.symbol(nestedAMemberSym))

                let unrelatedClassSym = defineSymbol(symbols, interner: interner, kind: .class, name: "UnrelatedClass", visibility: .public)

                // Access from outer class to nested private member
                #expect(checker.isAccessible(nestedAMember, fromFile: FileID(rawValue: 0), enclosingClass: outerClassSym))
                // Access from sibling nested class to nested private member
                #expect(checker.isAccessible(nestedAMember, fromFile: FileID(rawValue: 0), enclosingClass: nestedBSym))
                // Access from unrelated class should be rejected
                #expect(!checker.isAccessible(nestedAMember, fromFile: FileID(rawValue: 0), enclosingClass: unrelatedClassSym))

            }

        }
    }

}
