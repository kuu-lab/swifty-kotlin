#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ConstantCollectorTests {
    let collector = ConstantCollector()
    let interner = StringInterner()

    private static let sharedPosSources: [String] = [
            """
            package sample13
            val answer = 42
            """,
            """
            package sample14
            val flag = true
            """,
            """
            package sample16
            val neg = -100
            """,
            """
            package sample17
            val flag = !false
            """
    ]

    private static let sharedNegSources: [String] = [
            """
            package sample18
            fun compute() = 42
            val x = compute()
            """
    ]

    private static nonisolated(unsafe) var _sharedPosCtx: CompilationContext?
    private static nonisolated(unsafe) var _sharedNegCtx: CompilationContext?

    private func sharedPosCtx() throws -> CompilationContext {
        if let cached = Self._sharedPosCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedPosSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedPosCtx = ctx
        return ctx
    }

    private func sharedNegCtx() throws -> CompilationContext {
        if let cached = Self._sharedNegCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFiles(contents: Self.sharedNegSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedNegCtx = ctx
        return ctx
    }

    private func buildSourceByFileID(ctx: CompilationContext) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for fileID in ctx.sourceManager.fileIDs() {
            let data = ctx.sourceManager.contents(of: fileID)
            result[fileID.rawValue] = String(decoding: data, as: UTF8.self)
        }
        return result
    }

    @Test func testInlineGetterExtractsIntegerLiteral() {
        let source = "val x: Int\n    get() = 42"
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: source, interner: interner)
        #expect(result == .intLiteral(42))
    }

    @Test func testInlineGetterExtractsNegativeIntegerLiteral() {
        let source = "val x: Int\n    get() = -100"
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: source, interner: interner)
        #expect(result == .intLiteral(-100))
    }

    @Test func testInlineGetterExtractsIntLiteralWithUnderscores() {
        let source = "val MAX: Int\n    get() = 1_000_000"
        let result = collector.inlineGetterConstantExpr(propertyName: "MAX", source: source, interner: interner)
        #expect(result == .intLiteral(1_000_000))
    }

    @Test func testInlineGetterExtractsBoolTrue() {
        let source = "val flag: Boolean\n    get() = true"
        let result = collector.inlineGetterConstantExpr(propertyName: "flag", source: source, interner: interner)
        #expect(result == .boolLiteral(true))
    }

    @Test func testInlineGetterExtractsBoolFalse() {
        let source = "val flag: Boolean\n    get() = false"
        let result = collector.inlineGetterConstantExpr(propertyName: "flag", source: source, interner: interner)
        #expect(result == .boolLiteral(false))
    }

    @Test func testInlineGetterExtractsStringLiteral() {
        let source = "val name: String\n    get() = \"hello\""
        let result = collector.inlineGetterConstantExpr(propertyName: "name", source: source, interner: interner)
        let expected = interner.intern("hello")
        #expect(result == .stringLiteral(expected))
    }

    @Test func testInlineGetterExtractsEmptyStringLiteral() {
        let source = "val empty: String\n    get() = \"\""
        let result = collector.inlineGetterConstantExpr(propertyName: "empty", source: source, interner: interner)
        let expected = interner.intern("")
        #expect(result == .stringLiteral(expected))
    }

    @Test func testInlineGetterReturnsNilForEmptyPropertyName() {
        let source = "val x: Int\n    get() = 42"
        let result = collector.inlineGetterConstantExpr(propertyName: "", source: source, interner: interner)
        #expect(result == nil)
    }

    @Test func testInlineGetterReturnsNilForComplexExpression() {
        let source = "val x: Int\n    get() = someFunction()"
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: source, interner: interner)
        #expect(result == nil)
    }

    @Test func testCollectIntLiteralFromTopLevelVal() throws {
        let ctx = try sharedPosCtx()
        guard let ast = ctx.ast, let sema = ctx.sema else {
            Issue.record("AST/Sema module not available")
            return
        }
        let sourceByFileID = buildSourceByFileID(ctx: ctx)
        let mapping = collector.collectPropertyConstantInitializers(
            ast: ast, sema: sema, interner: ctx.interner, sourceByFileID: sourceByFileID
        )
        #expect(!mapping.isEmpty, "Should have collected at least one constant")
        let hasIntLiteral = mapping.values.contains { if case .intLiteral(42) = $0 { return true }; return false }
        #expect(hasIntLiteral, "Expected intLiteral(42) in mapping, got: \(mapping.values)")
    }

    @Test func testCollectBoolLiteralFromTopLevelVal() throws {
        let ctx = try sharedPosCtx()
        guard let ast = ctx.ast, let sema = ctx.sema else {
            Issue.record("AST/Sema module not available")
            return
        }
        let sourceByFileID = buildSourceByFileID(ctx: ctx)
        let mapping = collector.collectPropertyConstantInitializers(
            ast: ast, sema: sema, interner: ctx.interner, sourceByFileID: sourceByFileID
        )
        let hasBoolLiteral = mapping.values.contains { if case .boolLiteral(true) = $0 { return true }; return false }
        #expect(hasBoolLiteral, "Expected boolLiteral(true) in mapping")
    }

    @Test func testCollectStringLiteralFromTopLevelVal() throws {
        let ctx = try sharedPosCtx()
        guard let ast = ctx.ast, let sema = ctx.sema else {
            Issue.record("AST/Sema module not available")
            return
        }
        let sourceByFileID = buildSourceByFileID(ctx: ctx)
        let mapping = collector.collectPropertyConstantInitializers(
            ast: ast, sema: sema, interner: ctx.interner, sourceByFileID: sourceByFileID
        )
        let hasStringLiteral = mapping.values.contains {
            if case .stringLiteral = $0 { return true }; return false
        }
        #expect(hasStringLiteral, "Expected stringLiteral in mapping")
    }

    @Test func testCollectNegativeIntLiteralViaUnaryMinus() throws {
        let ctx = try sharedPosCtx()
        guard let ast = ctx.ast, let sema = ctx.sema else {
            Issue.record("AST/Sema module not available")
            return
        }
        let sourceByFileID = buildSourceByFileID(ctx: ctx)
        let mapping = collector.collectPropertyConstantInitializers(
            ast: ast, sema: sema, interner: ctx.interner, sourceByFileID: sourceByFileID
        )
        let hasNegInt = mapping.values.contains { if case .intLiteral(-100) = $0 { return true }; return false }
        #expect(hasNegInt, "Expected intLiteral(-100) in mapping")
    }

    @Test func testCollectBoolNegationViaUnaryNot() throws {
        let ctx = try sharedPosCtx()
        guard let ast = ctx.ast, let sema = ctx.sema else {
            Issue.record("AST/Sema module not available")
            return
        }
        let sourceByFileID = buildSourceByFileID(ctx: ctx)
        let mapping = collector.collectPropertyConstantInitializers(
            ast: ast, sema: sema, interner: ctx.interner, sourceByFileID: sourceByFileID
        )
        let hasBoolTrue = mapping.values.contains { if case .boolLiteral(true) = $0 { return true }; return false }
        #expect(hasBoolTrue, "Expected boolLiteral(true) for !false")
    }

    @Test func testNonLiteralInitializerNotCollected() throws {
        let ctx = try sharedNegCtx()
        guard let ast = ctx.ast, let sema = ctx.sema else {
            Issue.record("AST/Sema module not available")
            return
        }
        let sourceByFileID = buildSourceByFileID(ctx: ctx)
        let mapping = collector.collectPropertyConstantInitializers(
            ast: ast, sema: sema, interner: ctx.interner, sourceByFileID: sourceByFileID
        )
        let hasIntLiteral42 = mapping.values.contains { if case .intLiteral(42) = $0 { return true }; return false }
        #expect(!hasIntLiteral42, "Function call result should not be collected as constant")
    }
}
#endif
