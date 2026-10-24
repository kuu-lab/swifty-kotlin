#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct IntegerLiteralRangeTests {
    private func buildFrontend(_ source: String) throws -> (CompilationContext, ASTModule, FileID) {
        var result: (CompilationContext, ASTModule, FileID)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runFrontend(ctx)
            result = (ctx, try #require(ctx.ast), try #require(ctx.sourceManager.fileIDs().first))
        }
        return try #require(result)
    }

    private func localInitializers(
        in ast: ASTModule,
        fileID: FileID,
        interner: StringInterner
    ) -> [String: ExprID] {
        Dictionary(uniqueKeysWithValues: ast.arena.exprs.enumerated().compactMap { (index, expr) -> (String, ExprID)? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .localDecl(name, _, _, initializer?, _, _, _) = expr,
                  ast.arena.exprRange(exprID)?.start.file == fileID
            else {
                return nil
            }
            return (interner.resolve(name), initializer)
        })
    }

    @Test
    func unsuffixedLiteralsWidenAtInt32Boundary() throws {
        let source = """
        fun probe() {
            val decimal = 4294967296
            val hexadecimal = 0x80000000
            val unsigned = 4294967296u
            val small = 2147483647
        }
        """
        let (ctx, ast, fileID) = try buildFrontend(source)
        let initializers = localInitializers(in: ast, fileID: fileID, interner: ctx.interner)

        guard let decimal = initializers["decimal"],
              let hexadecimal = initializers["hexadecimal"],
              let unsigned = initializers["unsigned"],
              let small = initializers["small"]
        else {
            Issue.record("Expected all integer literal local declarations in the user source")
            return
        }

        guard case .longLiteral(4294967296, _) = ast.arena.expr(decimal) else {
            Issue.record("4294967296 must be represented as a Long literal in the AST")
            return
        }
        guard case .longLiteral(2147483648, _) = ast.arena.expr(hexadecimal) else {
            Issue.record("0x80000000 must be represented as a Long literal in the AST")
            return
        }
        guard case .ulongLiteral(4294967296, _) = ast.arena.expr(unsigned) else {
            Issue.record("4294967296u must be represented as a ULong literal in the AST")
            return
        }
        guard case .intLiteral(2147483647, _) = ast.arena.expr(small) else {
            Issue.record("2147483647 must remain an Int literal in the AST")
            return
        }

        try SemaPhase().run(ctx)
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.exprType(for: decimal) == sema.types.longType)
        #expect(sema.bindings.exprType(for: hexadecimal) == sema.types.longType)
        #expect(sema.bindings.exprType(for: unsigned) == sema.types.ulongType)
        #expect(sema.bindings.exprType(for: small) == sema.types.intType)
    }

    @Test
    func smallUnsignedRangeFallbackPromotesToUInt() throws {
        let source = """
        fun iterateSmallUnsignedRanges(
            byteLower: UByte,
            byteUpper: UByte,
            shortLower: UShort,
            shortUpper: UShort
        ) {
            for (byteValue in byteLower..byteUpper) {
                val promotedByte: UInt = byteValue
            }
            for (shortValue in shortLower..shortUpper) {
                val promotedShort: UInt = shortValue
            }
        }
        """
        let (ctx, ast, fileID) = try buildFrontend(source)

        try SemaPhase().run(ctx)

        let sema = try #require(ctx.sema)
        let rangeExprIDs = ast.arena.exprs.enumerated().compactMap { (index, expr) -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .binary(op, _, _, _) = expr,
                  op == .rangeTo,
                  ast.arena.exprRange(exprID)?.start.file == fileID
            else {
                return nil
            }
            return exprID
        }
        let loopIDsByName = Dictionary(uniqueKeysWithValues: ast.arena.exprs.enumerated().compactMap { (index, expr) -> (String, ExprID)? in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .forExpr(loopVariable?, _, _, _, _, _) = expr,
                  ast.arena.exprRange(exprID)?.start.file == fileID
            else {
                return nil
            }
            return (ctx.interner.resolve(loopVariable), exprID)
        })

        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error },
                "Small unsigned ranges must allow UInt-valued loop elements: \(ctx.diagnostics.diagnostics)")
        #expect(rangeExprIDs.count == 2)
        for rangeExpr in rangeExprIDs {
            #expect(sema.bindings.exprType(for: rangeExpr) == sema.types.uintType)
            #expect(sema.bindings.isUIntRangeExpr(rangeExpr))
        }
        for loopVariable in ["byteValue", "shortValue"] {
            let forExpr = try #require(loopIDsByName[loopVariable])
            let loopVariableSymbol = try #require(sema.bindings.identifierSymbol(for: forExpr))
            #expect(sema.symbols.propertyType(for: loopVariableSymbol) == sema.types.uintType)
        }
    }

    @Test
    func signedLiteralsBeyondInt64DoNotWrapToNegativeValues() throws {
        let source = """
        val hexadecimal = 0xFFFFFFFFFFFFFFFF
        val decimal = 9223372036854775808
        val suffixed = 9223372036854775808L
        """
        let (ctx, _, _) = try buildFrontend(source)
        let overflowDiagnostics = ctx.diagnostics.diagnostics.filter { $0.code == "KSWIFTK-LEX-0002" }
        #expect(overflowDiagnostics.count == 3, "Expected one overflow diagnostic per out-of-range literal, got: \(overflowDiagnostics)")
    }

    @Test
    func minimumIntLiteralsRemainValidAcrossRadices() throws {
        let source = """
        fun probe() {
            val decimal: Int = -2147483648
            val hexadecimal: Int = -0x80000000
            val binary: Int = -0b10000000000000000000000000000000
        }
        """
        let (ctx, ast, fileID) = try buildFrontend(source)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error })

        let initializers = localInitializers(in: ast, fileID: fileID, interner: ctx.interner)
        for name in ["decimal", "hexadecimal", "binary"] {
            let initializer = try #require(initializers[name])
            guard case .intLiteral(Int64(Int32.min), _) = ast.arena.expr(initializer) else {
                Issue.record("Expected \(name) to fold to Int.MIN_VALUE")
                continue
            }
        }

        try SemaPhase().run(ctx)
        let sema = try #require(ctx.sema)
        for name in ["decimal", "hexadecimal", "binary"] {
            let initializer = try #require(initializers[name])
            #expect(sema.bindings.exprType(for: initializer) == sema.types.intType)
        }
    }

    @Test
    func integerConstantBinaryExpressionAdaptsToExpectedLong() throws {
        let source = """
        fun value(): Long = 2147483647 + 1
        fun probe() {
            val a: Long = 2147483647 + 1
            val b: Long = 1 + 2
            val c: Long = (10 - 3) * 2
            val d: Long = 10 / 2
            val e: Long = 10 % 3
        }
        """
        let (ctx, _, _) = try buildFrontend(source)
        try SemaPhase().run(ctx)
        #expect(!ctx.diagnostics.diagnostics.contains { $0.severity == .error },
                "Expected all integer constant binary expressions to typecheck as Long: \(ctx.diagnostics.diagnostics)")
    }

    @Test
    func nonConstantIntegerBinaryExpressionRejectedForExpectedLong() throws {
        let source = """
        fun probe() {
            val x = 1
            val a: Long = x + 1
        }
        """
        let (ctx, _, _) = try buildFrontend(source)
        try SemaPhase().run(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-TYPE-0001" },
                "Expected non-constant Int expression to be rejected with KSWIFTK-TYPE-0001")
    }

    @Test
    func intConstantExpressionsWidenToLongArgumentsAndInitializers() throws {
        let source = """
        class Box(val a: Long)
        fun take(x: Long) = x
        fun probe(n: Int) {
            Box(1 shl 31)
            take(1 shl 16)
            take(2 * 3 + 1)
            take(-(1 shl 3))
            take(-(1 shl 31))
            take(7 and 3 xor 1)
            val x: Long = 1 shl 31
        }
        """
        let (ctx, ast, fileID) = try buildFrontend(source)
        try SemaPhase().run(ctx)
        let sema = try #require(ctx.sema)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Int literal-only constant expressions must coerce to Long: \(errors)")

        // kotlinc evaluates the expression with Int semantics, then widens it.
        let expected: [Int64] = [-2147483648, 65536, 7, -8, -2147483648, 2, -2147483648]
        let widened = ast.arena.exprs.enumerated().compactMap { (index, expr) -> Int64? in
            let exprID = ExprID(rawValue: Int32(index))
            switch expr {
            case .binary, .memberCall, .unaryExpr:
                guard ast.arena.exprRange(exprID)?.start.file == fileID,
                      sema.bindings.exprType(for: exprID) == sema.types.longType,
                      case let .longLiteral(value)? = sema.bindings.constExprValue(for: exprID)
                else { return nil }
                return value
            default:
                return nil
            }
        }
        #expect(widened.sorted() == expected.sorted(), "Widened constant values: \(widened)")
    }

    @Test
    func nonLiteralIntConstantExpressionStillRejectedForLongArgument() throws {
        let source = """
        fun take(x: Long) = x
        fun probe(n: Int) {
            take(n shl 2)
            take(Int.MAX_VALUE + 1)
        }
        """
        let (ctx, _, _) = try buildFrontend(source)
        try SemaPhase().run(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.contains { $0.code == "KSWIFTK-SEMA-0002" },
                "Non-literal Int expressions must not be widened to Long: \(errors)")
    }
}
#endif
