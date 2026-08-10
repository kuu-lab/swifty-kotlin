#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-FN: Consolidated Sema coverage for `String.toInt/toLong/toShort/toByte/
/// toFloat/toDouble` and their radix overloads. A single `runSema(ctx)` resolves all
/// source packages and each `do` block verifies the expected runtime bridge / return type.
@Suite
struct StringToNumericFunctionTests {
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
        for index in ast.arena.exprs.indices.reversed() {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path
            else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    @Test
    func testStringToNumericResolvesInSource() throws {
        let sources: [String] = [
            """
            package sample0
            fun parseInt(value: String): Int {
                return value.toInt()
            }

            fun parseIntHex(value: String): Int {
                return value.toInt(16)
            }
            """,
            """
            package sample1
            fun parseLong(raw: String): Long {
                return raw.toLong()
            }
            """,
            """
            package sample2
            fun parseShort(raw: String): Short {
                return raw.toShort()
            }

            fun probeShort(): Int {
                return "1000".toShort().toInt()
            }
            """,
            """
            package sample3
            fun parseByteDecimal(s: String): Int {
                return s.toByte().toInt()
            }

            fun parseByteHex(s: String): Int {
                return s.toByte(16).toInt()
            }

            fun parseByteBinary(s: String): Int {
                return s.toByte(2).toInt()
            }

            fun decimalByte(): Int {
                return "42".toByte().toInt()
            }

            fun hexByte(): Int {
                return "7f".toByte(16).toInt()
            }
            """,
            """
            package sample4
            fun parseFloatFromVariable(text: String): Float {
                return text.toFloat()
            }

            fun parseFloatFromLiteral(): Float {
                return "3.14".toFloat()
            }

            fun parseFloatNegative(): Float {
                return "-2.5".toFloat()
            }

            fun parseFloatInExpression(text: String): Float {
                return text.toFloat() + 1.0f
            }

            fun parseFloatInIfBranch(text: String): Float {
                return if (text.isNotEmpty()) text.toFloat() else 0.0f
            }
            """,
            """
            package sample5
            fun parseDoubleFromVariable(text: String): Double {
                return text.toDouble()
            }

            fun parseDoubleFromLiteral(): Double {
                return "3.14".toDouble()
            }

            fun parseDoubleNegative(): Double {
                return "-2.5".toDouble()
            }

            fun parseDoubleInExpression(text: String): Double {
                return text.toDouble() + 1.0
            }

            fun parseDoubleInIfBranch(text: String): Double {
                return if (text.isNotEmpty()) text.toDouble() else 0.0
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for path in paths {
                let pathDiagnostics = diagnosticsForPath(path, in: ctx)
                #expect(
                    !pathDiagnostics.contains(where: { $0.severity == .error }),
                    "Expected String-to-numeric conversions to resolve cleanly, got: \(pathDiagnostics)"
                )
            }

            // === toInt ===
            do {

                let path = paths[0]
                let toIntFQ = ["kotlin", "text", "toInt"].map { interner.intern($0) }
                let allLinks = Set(
                    sema.symbols.lookupAll(fqName: toIntFQ)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(
                    allLinks.contains("kk_string_toInt"),
                    "lookupAll for toInt must include kk_string_toInt; got: \(allLinks)"
                )
                #expect(
                    allLinks.contains("kk_string_toInt_radix"),
                    "lookupAll for toInt must include kk_string_toInt_radix; got: \(allLinks)"
                )

                let noArgCall = try #require(
                    lastExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == "toInt",
                              args.isEmpty
                        else { return false }
                        return true
                    },
                    "Expected member call to toInt() in sample0"
                )
                let noArgCallee = try #require(
                    sema.bindings.callBinding(for: noArgCall)?.chosenCallee,
                    "Expected call binding for toInt()"
                )
                #expect(
                    sema.symbols.externalLinkName(for: noArgCallee) == "kk_string_toInt",
                    "String.toInt() should resolve to kk_string_toInt"
                )

                let radixCall = try #require(
                    lastExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == "toInt",
                              args.count == 1
                        else { return false }
                        return true
                    },
                    "Expected member call to toInt(radix) in sample0"
                )
                let radixCallee = try #require(
                    sema.bindings.callBinding(for: radixCall)?.chosenCallee,
                    "Expected call binding for toInt(radix)"
                )
                #expect(
                    sema.symbols.externalLinkName(for: radixCallee) == "kk_string_toInt_radix",
                    "String.toInt(radix) should resolve to kk_string_toInt_radix"
                )
            }

            // === toLong ===
            do {

                let path = paths[1]
                let toLongFQ = ["kotlin", "text", "toLong"].map { interner.intern($0) }
                let toLongCall = try #require(
                    firstExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == "toLong",
                              args.isEmpty
                        else { return false }
                        return true
                    },
                    "Expected member call to toLong() in sample1"
                )
                let toLongCallee = try #require(
                    sema.bindings.callBinding(for: toLongCall)?.chosenCallee,
                    "Expected call binding for toLong"
                )
                #expect(
                    sema.symbols.externalLinkName(for: toLongCallee) == "kk_string_toLong",
                    "String.toLong() should resolve to kk_string_toLong"
                )

                let toLongSymbol = try #require(sema.symbols.lookup(fqName: toLongFQ))
                #expect(
                    sema.symbols.externalLinkName(for: toLongSymbol) == "kk_string_toLong",
                    "String.toLong should link to kk_string_toLong"
                )
            }

            // === toShort ===
            do {

                let toShortFQ = ["kotlin", "text", "toShort"].map { interner.intern($0) }
                let allLinks = Set(
                    sema.symbols.lookupAll(fqName: toShortFQ)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(
                    allLinks.contains("kk_string_toShort"),
                    "lookupAll for toShort must include kk_string_toShort; got: \(allLinks)"
                )

                let toShortSymbol = try #require(sema.symbols.lookup(fqName: toShortFQ))
                #expect(
                    sema.symbols.externalLinkName(for: toShortSymbol) == "kk_string_toShort",
                    "String.toShort should link to kk_string_toShort"
                )
            }

            // === toByte ===
            do {

                let toByteFQ = ["kotlin", "text", "toByte"].map { interner.intern($0) }
                let allLinks = Set(
                    sema.symbols.lookupAll(fqName: toByteFQ)
                        .compactMap { sema.symbols.externalLinkName(for: $0) }
                )
                #expect(allLinks.contains("kk_string_toByte"))
                #expect(allLinks.contains("kk_string_toByte_radix"))
            }

            // === toFloat ===
            do {

                let path = paths[4]
                let toFloatFQ = ["kotlin", "text", "toFloat"].map { interner.intern($0) }
                let toFloatCall = try #require(
                    lastExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == "toFloat",
                              args.isEmpty
                        else { return false }
                        return true
                    },
                    "Expected member call to toFloat() in sample4"
                )
                let toFloatCallee = try #require(
                    sema.bindings.callBinding(for: toFloatCall)?.chosenCallee,
                    "Expected call binding for toFloat"
                )
                let toFloatLink = sema.symbols.externalLinkName(for: toFloatCallee)
                #expect(
                    toFloatLink == nil || toFloatLink?.isEmpty == true,
                    "String.toFloat() should resolve to standard library function (no direct external link)"
                )

                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: toFloatFQ).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.receiverType == sema.types.stringType
                            && signature.parameterTypes.isEmpty
                    }
                )
                #expect(
                    sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.floatType,
                    "String.toFloat() should return Float"
                )
                let directLink = sema.symbols.externalLinkName(for: symbol)
                #expect(directLink == nil || directLink?.isEmpty == true)

                let privateFq = ["kotlin", "text", "__kk_string_toFloat"].map { interner.intern($0) }
                let privateSymbol = sema.symbols.lookup(fqName: privateFq)
                #expect(privateSymbol != nil)
                #expect(sema.symbols.externalLinkName(for: privateSymbol!) == "__kk_string_toFloat")
            }

            // === toDouble ===
            do {

                let path = paths[5]
                let toDoubleFQ = ["kotlin", "text", "toDouble"].map { interner.intern($0) }
                let toDoubleCall = try #require(
                    lastExprIDInPath(in: ast, path: path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, args, _) = expr,
                              interner.resolve(callee) == "toDouble",
                              args.isEmpty
                        else { return false }
                        return true
                    },
                    "Expected member call to toDouble() in sample5"
                )
                let toDoubleCallee = try #require(
                    sema.bindings.callBinding(for: toDoubleCall)?.chosenCallee,
                    "Expected call binding for toDouble"
                )
                let toDoubleLink = sema.symbols.externalLinkName(for: toDoubleCallee)
                #expect(
                    toDoubleLink == nil || toDoubleLink?.isEmpty == true,
                    "String.toDouble() should resolve to standard library function (no direct external link)"
                )

                let symbol = try #require(
                    sema.symbols.lookupAll(fqName: toDoubleFQ).first { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else { return false }
                        return signature.receiverType == sema.types.stringType
                            && signature.parameterTypes.isEmpty
                    }
                )
                #expect(
                    sema.symbols.functionSignature(for: symbol)?.returnType == sema.types.doubleType,
                    "String.toDouble() should return Double"
                )
                let directLink = sema.symbols.externalLinkName(for: symbol)
                #expect(directLink == nil || directLink?.isEmpty == true)

                let privateFq = ["kotlin", "text", "__kk_string_toDouble"].map { interner.intern($0) }
                let privateSymbol = sema.symbols.lookup(fqName: privateFq)
                #expect(privateSymbol != nil)
                #expect(sema.symbols.externalLinkName(for: privateSymbol!) == "__kk_string_toDouble")
            }
        }
    }
}
#endif
