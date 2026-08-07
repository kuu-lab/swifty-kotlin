#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN: Consolidated Sema coverage for `String.toIntOrNull/toLongOrNull/
/// toShortOrNull/toByteOrNull/toFloatOrNull/toDoubleOrNull/toBigIntegerOrNull/
/// toBigDecimalOrNull`. A single `runSema(ctx)` resolves all source packages and
/// each `do` block verifies the expected nullable return type / runtime bridge.
@Suite
struct StringToNullableNumericFunctionTests {
    private func allMemberCallExprIDsInPath(
        named member: String,
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        interner: StringInterner
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, callee, _, _, _) = expr,
                  interner.resolve(callee) == member,
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else {
                return nil
            }
            return exprID
        }
    }

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

    private func externalLink(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let fq = ["kotlin", "text", member].map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: fq)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    private func bigIntegerType(
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let fq = ["java", "math", "BigInteger"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func bigDecimalType(
        sema: SemaModule,
        interner: StringInterner
    ) throws -> TypeID {
        let fq = ["java", "math", "BigDecimal"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fq))
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    @Test
    func testStringToNullableNumericResolvesInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun probeNoRadix(text: String) {
                val result: Int? = text.toIntOrNull()
                println(result)
            }

            fun probeRadix(text: String) {
                val result: Int? = text.toIntOrNull(16)
                println(result)
            }

            fun probeLiteral(): Int {
                val parsed: Int? = "42".toIntOrNull()
                return parsed ?: 0
            }
            """,
            """
            package sample1
            fun parse(raw: String): Long? {
                return raw.toLongOrNull()
            }
            """,
            """
            package sample2
            fun parse(raw: String): Short? {
                return raw.toShortOrNull()
            }

            fun probe(): Int {
                val parsed = "32767".toShortOrNull()
                return parsed ?: 0
            }
            """,
            """
            package sample3
            fun parse(raw: String): Byte? {
                return raw.toByteOrNull()
            }

            fun probe(): Int {
                val parsed = "127".toByteOrNull()
                return parsed ?: 0
            }
            """,
            """
            package sample4
            fun probe(text: String) {
                val result: Double? = text.toDoubleOrNull()
                println(result)
            }

            fun probeLiteral(): Double {
                val parsed: Double? = "3.14".toDoubleOrNull()
                return parsed ?: 0.0
            }

            fun parse(raw: String): Double? {
                return raw.toDoubleOrNull()
            }
            """,
            """
            package sample5
            fun parse(raw: String): Float? {
                return raw.toFloatOrNull()
            }

            fun safeParse(raw: String): Float {
                return raw.toFloatOrNull() ?: 0.0f
            }
            """,
            """
            package sample6
            import java.math.BigInteger

            fun parse(raw: String): BigInteger? {
                return raw.toBigIntegerOrNull()
            }
            """,
            """
            package sample7
            import java.math.BigDecimal

            fun probe(text: String) {
                val result: BigDecimal? = text.toBigDecimalOrNull()
                println(result)
            }

            fun parse(raw: String): BigDecimal {
                return raw.toBigDecimalOrNull() ?: "0".toBigDecimal()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            #expect(
                !ctx.diagnostics.hasError,
                "Expected String-to-nullable-numeric conversions to resolve cleanly, got: \(ctx.diagnostics.diagnostics)"
            )

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === toIntOrNull ===
            do {

                let path = paths[0]
                let intOrNullFQ = ["kotlin", "text", "toIntOrNull"].map { interner.intern($0) }
                let links = Set(
                    sema.symbols.lookupAll(fqName: intOrNullFQ)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(
                    links.contains("kk_string_toIntOrNull_flat"),
                    "lookupAll for toIntOrNull must include kk_string_toIntOrNull_flat; got: \(links)"
                )
                #expect(
                    links.contains("kk_string_toIntOrNull_radix_flat"),
                    "lookupAll for toIntOrNull must include kk_string_toIntOrNull_radix_flat; got: \(links)"
                )

                let noRadixCall = try #require(
                    firstExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == "toIntOrNull",
                              args.isEmpty
                        else { return false }
                        return true
                    },
                    "Expected member call to toIntOrNull() in sample0"
                )
                #expect(
                    sema.bindings.exprType(for: noRadixCall) == sema.types.makeNullable(sema.types.intType)
                )

                let radixCall = try #require(
                    firstExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == "toIntOrNull",
                              args.count == 1
                        else { return false }
                        return true
                    },
                    "Expected member call to toIntOrNull(radix) in sample0"
                )
                #expect(
                    sema.bindings.exprType(for: radixCall) == sema.types.makeNullable(sema.types.intType)
                )
            }

            // === toLongOrNull ===
            do {

                #expect(
                    externalLink(for: "toLongOrNull", sema: sema, interner: interner) == "kk_string_toLongOrNull",
                    "String.toLongOrNull should link to kk_string_toLongOrNull"
                )

                let links = externalLinks(for: "toLongOrNull", sema: sema, interner: interner)
                #expect(
                    links.contains("kk_string_toLongOrNull"),
                    "lookupAll for toLongOrNull must include kk_string_toLongOrNull; got: \(links)"
                )
            }

            // === toShortOrNull ===
            do {

                let shortOrNullFQ = ["kotlin", "text", "toShortOrNull"].map { interner.intern($0) }
                let allLinks = Set(
                    sema.symbols.lookupAll(fqName: shortOrNullFQ)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(
                    allLinks.contains("kk_string_toShortOrNull"),
                    "lookupAll for toShortOrNull must include kk_string_toShortOrNull; got: \(allLinks)"
                )

                let directLink = sema.symbols.lookupAll(fqName: shortOrNullFQ).first.flatMap { sema.symbols.externalLinkName(for: $0) }
                #expect(
                    directLink == "kk_string_toShortOrNull",
                    "String.toShortOrNull should link to kk_string_toShortOrNull"
                )
            }

            // === toByteOrNull ===
            do {

                let byteOrNullFQ = ["kotlin", "text", "toByteOrNull"].map { interner.intern($0) }
                let allLinks = Set(
                    sema.symbols.lookupAll(fqName: byteOrNullFQ)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(
                    allLinks.contains("kk_string_toByteOrNull"),
                    "lookupAll for toByteOrNull must include kk_string_toByteOrNull; got: \(allLinks)"
                )

                let directLink = sema.symbols.lookupAll(fqName: byteOrNullFQ).first.flatMap { sema.symbols.externalLinkName(for: $0) }
                #expect(
                    directLink == "kk_string_toByteOrNull",
                    "String.toByteOrNull should link to kk_string_toByteOrNull"
                )
            }

            // === toDoubleOrNull ===
            do {

                let path = paths[4]
                let callIDs = allMemberCallExprIDsInPath(
                    named: "toDoubleOrNull",
                    in: ast,
                    path: path,
                    ctx: ctx,
                    interner: interner
                )
                let expectedType = sema.types.makeNullable(sema.types.doubleType)
                #expect(callIDs.count == 3, "Expected three toDoubleOrNull calls")
                for callExpr in callIDs {
                    #expect(
                        sema.bindings.exprType(for: callExpr) == expectedType,
                        "toDoubleOrNull must return Double?"
                    )
                }

                let directFq = ["kotlin", "text", "toDoubleOrNull"].map { interner.intern($0) }
                let directSymbol = try #require(
                    sema.symbols.lookupAll(fqName: directFq).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.receiverType == sema.types.stringType
                            && signature.parameterTypes.isEmpty
                    }
                )
                let directLink = sema.symbols.externalLinkName(for: directSymbol)
                #expect(
                    directLink == nil || directLink?.isEmpty == true,
                    "String.toDoubleOrNull should be source-backed and not have a direct external link"
                )

                #expect(
                    externalLink(for: "__kk_string_toDoubleOrNull", sema: sema, interner: interner) == "__kk_string_toDoubleOrNull",
                    "__kk_string_toDoubleOrNull should link to __kk_string_toDoubleOrNull"
                )
            }

            // === toFloatOrNull ===
            do {

                let path = paths[5]
                let callIDs = allMemberCallExprIDsInPath(
                    named: "toFloatOrNull",
                    in: ast,
                    path: path,
                    ctx: ctx,
                    interner: interner
                )
                #expect(callIDs.count == 2, "Expected two toFloatOrNull calls")
                let expectedType = sema.types.make(.primitive(.float, .nullable))
                for callExpr in callIDs {
                    #expect(
                        sema.bindings.exprType(for: callExpr) == expectedType,
                        "toFloatOrNull must return Float?"
                    )
                }

                let directFq = ["kotlin", "text", "toFloatOrNull"].map { interner.intern($0) }
                let directSymbol = try #require(
                    sema.symbols.lookupAll(fqName: directFq).first { symbolID in
                        guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return sig.receiverType == sema.types.stringType && sig.parameterTypes.isEmpty
                    }
                )
                let directLink = sema.symbols.externalLinkName(for: directSymbol)
                #expect(
                    directLink == nil || directLink?.isEmpty == true,
                    "String.toFloatOrNull should be source-backed and not have a direct external link"
                )

                let returnType = try #require(sema.symbols.functionSignature(for: directSymbol)?.returnType)
                #expect(
                    returnType == sema.types.make(.primitive(.float, .nullable)),
                    "String.toFloatOrNull() should return Float?"
                )

                #expect(
                    externalLink(for: "__kk_string_toFloatOrNull", sema: sema, interner: interner) == "__kk_string_toFloatOrNull",
                    "__kk_string_toFloatOrNull should link to __kk_string_toFloatOrNull"
                )
            }

            // === toBigIntegerOrNull ===
            do {

                let path = paths[6]
                let expectedType = sema.types.makeNullable(try bigIntegerType(sema: sema, interner: interner))
                let callIDs = allMemberCallExprIDsInPath(
                    named: "toBigIntegerOrNull",
                    in: ast,
                    path: path,
                    ctx: ctx,
                    interner: interner
                )
                #expect(callIDs.count == 1, "Expected one toBigIntegerOrNull call")
                for callExpr in callIDs {
                    #expect(sema.bindings.exprType(for: callExpr) == expectedType)
                }

                let directLink = externalLink(for: "toBigIntegerOrNull", sema: sema, interner: interner)
                #expect(
                    directLink == nil || directLink?.isEmpty == true,
                    "String.toBigIntegerOrNull should be source-backed and not have a direct external link"
                )
                #expect(
                    externalLink(for: "__kk_string_toBigIntegerOrNull", sema: sema, interner: interner) == "__kk_string_toBigIntegerOrNull",
                    "__kk_string_toBigIntegerOrNull should link to __kk_string_toBigIntegerOrNull"
                )
            }

            // === toBigDecimalOrNull ===
            do {

                let path = paths[7]
                let expectedType = sema.types.makeNullable(try bigDecimalType(sema: sema, interner: interner))
                let callIDs = allMemberCallExprIDsInPath(
                    named: "toBigDecimalOrNull",
                    in: ast,
                    path: path,
                    ctx: ctx,
                    interner: interner
                )
                #expect(callIDs.count == 2, "Expected two toBigDecimalOrNull calls")
                for callExpr in callIDs {
                    #expect(sema.bindings.exprType(for: callExpr) == expectedType)
                }

                let directLink = externalLink(for: "toBigDecimalOrNull", sema: sema, interner: interner)
                #expect(
                    directLink == nil || directLink?.isEmpty == true,
                    "String.toBigDecimalOrNull should be source-backed and not have a direct external link"
                )
                #expect(
                    externalLink(for: "__kk_string_toBigDecimalOrNull", sema: sema, interner: interner) == "__kk_string_toBigDecimalOrNull",
                    "__kk_string_toBigDecimalOrNull should link to __kk_string_toBigDecimalOrNull"
                )
            }
        }
    }
}
#endif
