#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite(.serialized)
struct BuildASTDeterminismTests {
    private func build(
        paths: [String], jobs: Int,
        cached: IncrementalFrontendState? = nil,
        changed: Set<String>? = nil
    ) throws -> CompilationContext {
        let ctx = makeCompilationContext(
            inputs: paths, frontendFlags: ["jobs=\(jobs)"], includeStdlib: false
        )
        try LoadSourcesPhase().run(ctx)
        if let cached, let changed {
            ctx.interner.preload(cached.internerValues)
            ctx.installIncrementalFrontendState(cached)
            ctx.setIncrementalRecompileSet(changed)
        }
        try LexPhase().run(ctx)
        try ParsePhase().run(ctx)
        try BuildASTPhase().run(ctx)
        return ctx
    }

    private func encoded<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    /// Compare every ID and side-table edge, without normalizing synthetic names.
    private func expectSameArena(_ actual: ASTArenaSnapshot, _ expected: ASTArenaSnapshot) throws {
        #expect(try encoded(actual.declarations) == encoded(expected.declarations))
        #expect(try encoded(actual.expressions) == encoded(expected.expressions))
        #expect(try encoded(actual.typeRefs) == encoded(expected.typeRefs))
        #expect(actual.loopLabels == expected.loopLabels)
        #expect(actual.whenSubjectVarNames == expected.whenSubjectVarNames)
        #expect(actual.whenSubjectTypeRefs == expected.whenSubjectTypeRefs)
        #expect(actual.lambdaParamTypeRefs == expected.lambdaParamTypeRefs)
        #expect(actual.callableRefReceiverTypeRefs == expected.callableRefReceiverTypeRefs)
        #expect(actual.infixCallExpressions == expected.infixCallExpressions)
        #expect(actual.infixFunctionExpressions == expected.infixFunctionExpressions)
        #expect(actual.operatorFunctionExpressions == expected.operatorFunctionExpressions)
        #expect(actual.explicitCallExpressions == expected.explicitCallExpressions)
        #expect(actual.receiverExpressionArgsCallExpressions == expected.receiverExpressionArgsCallExpressions)
        #expect(actual.incrementDecrementExpressions == expected.incrementDecrementExpressions)
        #expect(actual.callResultCompoundAssignmentBlocks == expected.callResultCompoundAssignmentBlocks)
        #expect(actual.nonFunctionLambdaLabels == expected.nonFunctionLambdaLabels)
        #expect(actual.incrementDecrementCachedValues == expected.incrementDecrementCachedValues)
        #expect(Set(actual.expressionAnnotations.keys) == Set(expected.expressionAnnotations.keys))
        for id in expected.expressionAnnotations.keys {
            #expect(try encoded(actual.expressionAnnotations[id]) == encoded(expected.expressionAnnotations[id]))
        }
        #expect(actual.anonymousFunctionExpressions == expected.anonymousFunctionExpressions)
        #expect(actual.parenthesizedExpressions == expected.parenthesizedExpressions)
    }

    private func expectSameAST(_ actual: CompilationContext, _ expected: CompilationContext) throws {
        let actualAST = try #require(actual.ast)
        let expectedAST = try #require(expected.ast)
        try expectSameArena(actualAST.arena.snapshot(), expectedAST.arena.snapshot())
        #expect(try encoded(actualAST.files) == encoded(expectedAST.files))
        #expect(actualAST.activeDeclsByFileRawID == expectedAST.activeDeclsByFileRawID)
        #expect(actualAST.declarationCount == expectedAST.declarationCount)
        #expect(actualAST.tokenCount == expectedAST.tokenCount)
        #expect(actual.interner.snapshotValues() == expected.interner.snapshotValues())
        #expect(actual.diagnostics.diagnostics == expected.diagnostics.diagnostics)
    }

    @Test(arguments: [false, true])
    func lambdaAndAdapterRawKIRIsIdenticalAcrossJobs(includeObjects: Bool) throws {
        var sources = [
            "fun make(x: Int): (Int) -> Int = { y: Int -> x + y }",
            "fun other(x: Int): Int = x + 1",
        ]
        if includeObjects {
            sources.append("""
            class Holder(val seed: Int) {
                class Nested(val value: Int) { fun read(): Int = value }
                object Fixed { fun read(): Int = 3 }
                fun run(delta: Int): Int {
                    fun local(y: Int): Int = seed + y
                    val captured = object { fun read(): Int = seed + delta }
                    val lambda = { y: Int -> local(y) }
                    return lambda(delta) + captured.read() + Nested(4).read() + Fixed.read()
                }
            }
            fun exercise(): Int = Holder(10).run(2)
            """)
        }
        try withTemporaryFiles(contents: sources) { paths in
            let baseline = try build(paths: paths, jobs: 1)
            try SemaPhase().run(baseline)
            try BuildKIRPhase().run(baseline)
            try LoweringPhase().run(baseline)
            #expect(!baseline.diagnostics.hasError)
            let dump = try #require(baseline.kir).dump(
                interner: baseline.interner, symbols: baseline.sema?.symbols
            )
            #expect(dump.contains("kk_lambda_6 "))
            #expect(dump.contains("kk_function_value_adapter_6_"))
            #expect(dump.contains("SymbolID(rawValue: -2001536)"))
            #expect(dump.contains("SymbolID(rawValue: -1001536)"))
            for jobs in [1, 2, 4] {
                for _ in 0 ..< 3 {
                    let ctx = try build(paths: paths, jobs: jobs)
                    try SemaPhase().run(ctx)
                    try BuildKIRPhase().run(ctx)
                    try LoweringPhase().run(ctx)
                    #expect(!ctx.diagnostics.hasError)
                    let actual = try #require(ctx.kir).dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
                    #expect(actual == dump, "Raw KIR differs for jobs=\(jobs)")
                }
            }
        }
    }

    /// Include the same annotations/syntax at nonzero offsets in all three ID spaces.
    private let richSource = """
    @file:Suppress("unused")
    @Tag("literal", value = "${1 + 2}")
    class Container<T : Any>(val seed: Int = 1) : Base(seed) {
        typealias Alias = Int
        val field: @Tag("type") Int = seed
        init { seed + 1 }
        constructor() : this(2) { seed + 2 }
        class Nested { fun value(): Int = 4 }
        object NestedObject { val value: Int = 5 }
        companion object { fun value(): Int = 6 }
        fun run(x: Int): Int {
            class Local(val value: Int) { fun get(): Int = value }
            fun local(y: Int = x): Int = y + 1
            val captured = object : Base(x) { fun get(): Int = x }
            val fn = label@{ y: Int -> x + y }
            val annotated = @Tag("expr") x
            val anonymous = fun(y: Int): Int = x + y
            val ref = Int::toString
            var n = x
            outer@ while (n < 3) { n++; if (n == 2) continue@outer }
            when (val subject: Int = n) { 0 -> n; else -> subject }
            return try { local(n) } catch (e: Exception) { 0 } finally { n + 1 }
        }
    }
    interface Contract { fun get(): Int; object Holder { val value: Int = 7 } }
    enum class Choice(val n: Int) { ONE(1) { fun value(): Int = n } }
    infix fun Int.join(other: Int): Int = this + other
    operator fun Container<Int>.plus(other: Int): Int = other
    fun calls(): Int { val fn = { 1 }; fn(); factory() += 1; return 1 join 2 }
    """

    @Test func mergedASTMatchesDirectSequentialConstruction() throws {
        try withTemporaryFiles(contents: [
            "fun prefix(x: Int): Int = x + 1", richSource, richSource,
        ]) { paths in
            let baseline = try build(paths: paths, jobs: 1)
            #expect(!baseline.diagnostics.hasError)
            let baselineSnapshot = try #require(baseline.ast).arena.snapshot()
            #expect(!baselineSnapshot.expressionAnnotations.isEmpty)
            #expect(!baselineSnapshot.anonymousFunctionExpressions.isEmpty)
            let legacy = makeCompilationContext(inputs: paths, includeStdlib: false)
            try LoadSourcesPhase().run(legacy)
            try LexPhase().run(legacy)
            try ParsePhase().run(legacy)
            let arena = ASTArena()
            let phase = BuildASTPhase(diagnostics: legacy.diagnostics)
            var files: [ASTFile] = []
            for (fileID, cst, root) in legacy.syntaxTrees {
                phase.tokenCache.removeAll()
                let file = phase.buildFileAST(fileID: fileID, cst: cst, root: root,
                                              interner: legacy.interner, arena: arena)
                files.append(ASTFile(fileID: fileID, packageFQName: file.packageFQName,
                                     imports: file.imports, topLevelDecls: file.topLevelDecls,
                                     scriptBody: file.scriptBody, annotations: file.annotations, range: file.range))
            }
            try expectSameArena(try #require(baseline.ast).arena.snapshot(), arena.snapshot())
            #expect(try encoded(try #require(baseline.ast).files) == encoded(files))
            #expect(baseline.interner.snapshotValues() == legacy.interner.snapshotValues())
            for jobs in [2, 4] {
                for _ in 0 ..< 3 {
                    try expectSameAST(build(paths: paths, jobs: jobs), baseline)
                }
            }
        }
    }

    @Test func incrementalArenaPrefixAndUnchangedFileReferencesArePreserved() throws {
        try withTemporaryFiles(contents: [
            "fun kept(x: Int): (Int) -> Int = { y: Int -> x + y }",
            "fun oldChanged(): Int = 1", "fun anotherChanged(): Int = 2",
        ]) { paths in
            let initial = try build(paths: paths, jobs: 1)
            let cached = try #require(IncrementalFrontendState(context: initial, buildConfigurationHash: "test"))
            try richSource.write(toFile: paths[1], atomically: true, encoding: .utf8)
            try "fun changed(x: Int): (Int) -> Int = { y: Int -> x + y }"
                .write(toFile: paths[2], atomically: true, encoding: .utf8)
            let changed = Set(paths.dropFirst())
            let baseline = try build(paths: paths, jobs: 1, cached: cached, changed: changed)
            #expect(!baseline.diagnostics.hasError)
            let ast = try #require(baseline.ast)
            #expect(try encoded(ast.files[0]) == encoded(cached.files[0]))
            #expect(ast.activeDeclsByFileRawID[0] == cached.activeDeclsByFileRawID[0])
            let snapshot = ast.arena.snapshot()
            #expect(try encoded(Array(snapshot.declarations.prefix(cached.arenaSnapshot.declarations.count)))
                    == encoded(cached.arenaSnapshot.declarations))
            #expect(Array(snapshot.expressions.prefix(cached.arenaSnapshot.expressions.count)) == cached.arenaSnapshot.expressions)
            #expect(Array(snapshot.typeRefs.prefix(cached.arenaSnapshot.typeRefs.count)) == cached.arenaSnapshot.typeRefs)
            for (id, types) in cached.arenaSnapshot.lambdaParamTypeRefs {
                #expect(snapshot.lambdaParamTypeRefs[id] == types)
            }
            let changedDecl = try #require(ast.files[2].topLevelDecls.first)
            #expect(Int(changedDecl.rawValue) >= cached.arenaSnapshot.declarations.count)
            guard case let .funDecl(function) = ast.arena.decl(changedDecl),
                  case let .expr(lambdaID, _) = function.body,
                  case let .lambdaLiteral(_, bodyID, _, _) = ast.arena.expr(lambdaID)
            else {
                Issue.record("Changed function must retain its lambda body")
                return
            }
            #expect(Int(lambdaID.rawValue) >= cached.arenaSnapshot.expressions.count)
            #expect(Int(bodyID.rawValue) >= cached.arenaSnapshot.expressions.count)
            let paramTypes = try #require(ast.arena.lambdaParamTypeRefs(for: lambdaID))
            #expect(paramTypes.compactMap { $0 }.allSatisfy {
                Int($0.rawValue) >= cached.arenaSnapshot.typeRefs.count
            })
            for jobs in [2, 4] {
                for _ in 0 ..< 3 {
                    try expectSameAST(build(paths: paths, jobs: jobs, cached: cached, changed: changed), baseline)
                }
            }
        }
    }

    @Test func scriptAndDiagnosticsKeepInputOrder() throws {
        try withTemporaryFiles(contents: [
            "fun first() {}\nval x = 1\nx + 2", "val broken = \"unterminated",
        ], fileExtension: "kts") { paths in
            let baseline = try build(paths: paths, jobs: 1)
            #expect(!baseline.diagnostics.diagnostics.isEmpty)
            #expect(!(try #require(baseline.ast).files[0].scriptBody.isEmpty))
            for jobs in [2, 4] {
                try expectSameAST(build(paths: paths, jobs: jobs), baseline)
            }
        }
    }

    @Test func reversedInputsRetainTheirDeclarationOrder() throws {
        try withTemporaryFiles(contents: ["fun first(): Int = 1", "fun second(): Int = 2"]) { paths in
            for jobs in [1, 2, 4] {
                let ctx = try build(paths: Array(paths.reversed()), jobs: jobs)
                let ast = try #require(ctx.ast)
                let names = ast.files.flatMap(\.topLevelDecls).compactMap { id -> String? in
                    guard case let .funDecl(function) = ast.arena.decl(id) else { return nil }
                    return ctx.interner.resolve(function.name)
                }
                #expect(names == ["second", "first"])
                #expect(ast.files.map { ctx.sourceManager.path(of: $0.fileID) } == Array(paths.reversed()))
            }
        }
    }

    @Test func snapshotSideTablesRemapBothKeysAndValuesAfterExistingPrefix() throws {
        let file = FileID(rawValue: 0)
        let range = SourceRange(start: SourceLocation(file: file, offset: 10),
                                end: SourceLocation(file: file, offset: 20))
        let expr = ExprID(rawValue: 0)
        let type = TypeRefID(rawValue: 0)
        let localName = InternedString(rawValue: 1)
        let sharedName = InternedString(rawValue: 7)
        let snapshot = ASTArenaSnapshot(
            declarations: [], expressions: [.nameRef(localName, range)],
            typeRefs: [.named(path: [localName], args: [], nullable: false)],
            loopLabels: [expr: localName], whenSubjectVarNames: [expr: localName],
            whenSubjectTypeRefs: [expr: type], lambdaParamTypeRefs: [expr: [type, nil]],
            callableRefReceiverTypeRefs: [expr: type], infixCallExpressions: [expr],
            infixFunctionExpressions: [expr], operatorFunctionExpressions: [expr],
            explicitCallExpressions: [expr], receiverExpressionArgsCallExpressions: [expr],
            incrementDecrementExpressions: [expr],
            callResultCompoundAssignmentBlocks: [expr], nonFunctionLambdaLabels: [expr],
            incrementDecrementCachedValues: [expr: expr],
            expressionAnnotations: [expr: [AnnotationNode(
                name: "Tag", constructionTokens: [Token(kind: .identifier(localName), range: range)]
            )]],
            anonymousFunctionExpressions: [expr]
        )
        let arena = ASTArena()
        let prefixRange = SourceRange(start: SourceLocation(file: file, offset: 0),
                                      end: SourceLocation(file: file, offset: 1))
        let prefixExpr = arena.appendExpr(.intLiteral(1, prefixRange))
        _ = arena.appendTypeRef(.named(path: [], args: [], nullable: false))
        // Prime the index before appending so a stale cache cannot hide the new file.
        #expect(arena.indexedInnermostExpr(at: 10, in: file) == nil)
        let remap = arena.appendFileSnapshot(snapshot, sharedStringCount: 1, addedStrings: [sharedName])
        let mergedExpr = ExprID(rawValue: 1)
        let mergedType = TypeRefID(rawValue: 1)
        #expect(remap.remap(ExprID.invalid) == .invalid)
        #expect(remap.remap(DeclID.invalid) == .invalid)
        #expect(remap.remap(TypeRefID.invalid) == .invalid)
        #expect(remap.remap(InternedString.invalid) == .invalid)
        #expect(arena.expr(prefixExpr) == .intLiteral(1, prefixRange))
        #expect(arena.expr(mergedExpr) == .nameRef(sharedName, range))
        #expect(arena.typeRef(mergedType) == .named(path: [sharedName], args: [], nullable: false))
        #expect(arena.loopLabel(for: mergedExpr) == sharedName)
        #expect(arena.whenSubjectVarName(for: mergedExpr) == sharedName)
        #expect(arena.whenSubjectTypeRef(for: mergedExpr) == mergedType)
        #expect(arena.lambdaParamTypeRefs(for: mergedExpr) == [mergedType, nil])
        #expect(arena.callableRefReceiverTypeRef(for: mergedExpr) == mergedType)
        #expect(arena.incrementDecrementCachedValue(for: mergedExpr) == mergedExpr)
        #expect(arena.isInfixCall(mergedExpr))
        #expect(arena.isInfixFunction(mergedExpr))
        #expect(arena.isOperatorFunction(mergedExpr))
        #expect(arena.isExplicitCall(mergedExpr))
        #expect(arena.isReceiverExpressionArgsCall(mergedExpr))
        #expect(arena.isIncrementDecrement(mergedExpr))
        #expect(arena.isCallResultCompoundAssignmentBlock(mergedExpr))
        #expect(arena.isNonFunctionLambdaLabel(mergedExpr))
        #expect(arena.isAnonymousFunction(mergedExpr))
        let annotation = try #require(arena.expressionAnnotations(for: mergedExpr).first)
        #expect(annotation.constructionTokens?.first?.kind == .identifier(sharedName))
        #expect(arena.indexedInnermostExpr(at: 10, in: file) == mergedExpr)
    }
}
#endif
