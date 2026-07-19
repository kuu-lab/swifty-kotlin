#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ConstantCollectorTests {
    let collector = ConstantCollector()
    let interner = StringInterner()

    // MARK: - inlineGetterConstantExpr: Int literals

    @Test func testInlineGetterExtractsIntegerLiteral() {
        let source = "val x: Int\n    get() = 42"
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: source, interner: interner)
        #expect(result == .intLiteral(42))
    }

    @Test func testInlineGetterExtractsNegativeIntegerLiteral() {
        let source = "val x: Int\n    get() = -100"
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: source, interner: interner)
        // The regex captures "-100" and Int64("-100") parses to -100
        #expect(result == .intLiteral(-100))
    }

    @Test func testInlineGetterExtractsIntLiteralWithUnderscores() {
        let source = "val MAX: Int\n    get() = 1_000_000"
        let result = collector.inlineGetterConstantExpr(propertyName: "MAX", source: source, interner: interner)
        #expect(result == .intLiteral(1_000_000))
    }

    @Test func testInlineGetterExtractsZero() {
        let source = "val ZERO: Int\n    get() = 0"
        let result = collector.inlineGetterConstantExpr(propertyName: "ZERO", source: source, interner: interner)
        #expect(result == .intLiteral(0))
    }

    // MARK: - inlineGetterConstantExpr: Bool literals

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

    // MARK: - inlineGetterConstantExpr: String literals

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

    // MARK: - inlineGetterConstantExpr: Nil cases

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

    @Test func testInlineGetterReturnsNilWhenPropertyNotPresent() {
        let source = "val y: Int\n    get() = 42"
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: source, interner: interner)
        #expect(result == nil)
    }

    @Test func testInlineGetterDoesNotMatchWrongPropertyName() {
        // "xx" should not match "x"
        let source = "val xx: Int\n    get() = 99\nval x: Int\n    get() = 42"
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: source, interner: interner)
        #expect(result == .intLiteral(42))
    }

    @Test func testInlineGetterReturnsNilForEmptySource() {
        let result = collector.inlineGetterConstantExpr(propertyName: "x", source: "", interner: interner)
        #expect(result == nil)
    }

    // MARK: - literalConstantExpr via collectPropertyConstantInitializers

    @Test func testCollectIntLiteralFromTopLevelVal() throws {
        let ctx = makeContextFromSource("val answer = 42")
        try runSema(ctx)
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
        let ctx = makeContextFromSource("val flag = true")
        try runSema(ctx)
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
        let ctx = makeContextFromSource(#"val greeting = "hello""#)
        try runSema(ctx)
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
        let ctx = makeContextFromSource("val neg = -100")
        try runSema(ctx)
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
        let ctx = makeContextFromSource("val flag = !false")
        try runSema(ctx)
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
        let ctx = makeContextFromSource("""
        fun compute() = 42
        val x = compute()
        """)
        try runSema(ctx)
        guard let ast = ctx.ast, let sema = ctx.sema else {
            Issue.record("AST/Sema module not available")
            return
        }
        let sourceByFileID = buildSourceByFileID(ctx: ctx)
        let mapping = collector.collectPropertyConstantInitializers(
            ast: ast, sema: sema, interner: ctx.interner, sourceByFileID: sourceByFileID
        )
        // x should not be collected since it's a function call, not a literal
        let hasIntLiteral42 = mapping.values.contains { if case .intLiteral(42) = $0 { return true }; return false }
        #expect(!hasIntLiteral42, "Function call result should not be collected as constant")
    }

    // MARK: - Helpers

    private func buildSourceByFileID(ctx: CompilationContext) -> [Int32: String] {
        var result: [Int32: String] = [:]
        for fileID in ctx.sourceManager.fileIDs() {
            let data = ctx.sourceManager.contents(of: fileID)
            result[fileID.rawValue] = String(decoding: data, as: UTF8.self)
        }
        return result
    }
}
#endif
