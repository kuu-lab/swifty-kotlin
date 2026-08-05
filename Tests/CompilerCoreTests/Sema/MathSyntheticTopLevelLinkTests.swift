#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MathSyntheticTopLevelLinkTests {
    private func externalLink(for member: String, sema: SemaModule, interner: StringInterner) -> String? {
        let fq = ["kotlin", "math", member].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func mathExtensionProperty(
        named member: String,
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> (property: SymbolID, getter: SymbolID)? {
        let fq = ["kotlin", "math", member].map { interner.intern($0) }
        for symbolID in sema.symbols.lookupAll(fqName: fq) {
            guard sema.symbols.symbol(symbolID)?.kind == .property,
                  sema.symbols.extensionPropertyReceiverType(for: symbolID) == receiverType,
                  let getter = sema.symbols.extensionPropertyGetterAccessor(for: symbolID)
            else {
                continue
            }
            return (symbolID, getter)
        }
        return nil
    }

    // STDLIB-500..509: Float overloads resolve alongside Double overloads

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
            // testMathTopLevelSymbolsLinkToRuntimeFunctions
            """
            package sample0
            fun noop() {}
            """,
            // testFloatMathOverloadsHaveExternalLinks
            """
            package sample1
            fun noop() {}
            """,
            // testMathTopLevelCallsResolveWithKotlinMathImport
            """
            package sample2

                    import kotlin.math.*

                    fun sample(x: Int, y: Double): Double {
                        val ai = abs(-x)
                        val ad = abs(y)
                        return sqrt(ad * ad) + pow(ad, 2.0) + ceil(ad) + floor(ad) + round(ad)
                    }

            """,
            // testFloatingPrecisionHelpersResolveWithKotlinMathImport
            """
            package sample3

                    import kotlin.math.*

                    fun sample(x: Double, y: Float) {
                        val a = ulp(x)
                        val b = nextUp(x)
                        val c = nextDown(x)
                        val d = ulp(y)
                        val e = nextUp(y)
                        val f = nextDown(y)
                    }

            """,
            // testMathExtensionPropertySymbolsUseOfficialShape
            """
            package sample4
            fun noop() {}
            """,
            // testMathExtensionPropertiesResolveWithKotlinMathImport
            """
            package sample5

                    import kotlin.math.*

                    fun sample(i: Int, l: Long, f: Float, d: Double) {
                        val ai = i.absoluteValue
                        val al = l.absoluteValue
                        val af = f.absoluteValue
                        val ad = d.absoluteValue
                        val si = i.sign
                        val sl = l.sign
                        val sf = f.sign
                        val sd = d.sign
                        val uf = f.ulp
                        val ud = d.ulp
                    }

            """,
            // testDoublePowMemberCallResolvesViaMathExtensionStub
            """
            package sample6

                    import kotlin.math.*

                    fun sample(): Double {
                        return 2.0.pow(3.0)
                    }

            """,
            // testRemainingFloatingMathMemberCallsResolveViaDefaultImport
            """
            package sample7

                    import kotlin.math.*

                    fun sample(d: Double, f: Float, i: Int) {
                        val ieeeD = d.IEEErem(d)
                        val ieeeF = f.IEEErem(f)
                        val nextD = d.nextTowards(d)
                        val nextF = f.nextTowards(f)
                        val powF = f.pow(f)
                        val powDI = d.pow(i)
                        val powFI = f.pow(i)
                        val signD = d.withSign(d)
                        val signDI = d.withSign(i)
                        val signF = f.withSign(f)
                        val signFI = f.withSign(i)
                    }

            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in

            let ctx = makeCompilationContext(inputs: paths)

            try runSema(ctx)

            let ast = try #require(ctx.ast)

            let sema = try #require(ctx.sema)

            let interner = ctx.interner

            // === testMathTopLevelSymbolsLinkToRuntimeFunctions ===

            do {

                let sample0Path = paths[0]

                let sample0Diagnostics = diagnosticsForPath(sample0Path, in: ctx)

                let expected: [String: String] = [
                    "sqrt": "kk_math_sqrt",
                    "pow": "kk_math_pow",
                    "ceil": "kk_math_ceil",
                    "floor": "kk_math_floor",
                    "round": "kk_math_round",
                ]

                for (name, expectedLink) in expected {
                    #expect(
                        externalLink(for: name, sema: sema, interner: interner) == expectedLink,
                        "\(name) in kotlin.math should link to runtime"
                    )
                }

            }

            // === testFloatMathOverloadsHaveExternalLinks ===

            do {

                let sample1Path = paths[1]

                let sample1Diagnostics = diagnosticsForPath(sample1Path, in: ctx)

                // Each of these names should have at least two overloads registered
                // (Double and Float). Verify the Float variant has a link name.
                let floatOverloads: [(String, String)] = [
                    ("sin", "kk_math_sin_float"),
                    ("cos", "kk_math_cos_float"),
                    ("tan", "kk_math_tan_float"),
                    ("asin", "kk_math_asin_float"),
                    ("acos", "kk_math_acos_float"),
                    ("atan", "kk_math_atan_float"),
                    ("atan2", "kk_math_atan2_float"),
                    ("sqrt", "kk_math_sqrt_float"),
                    ("round", "kk_math_round_float"),
                    ("ceil", "kk_math_ceil_float"),
                    ("floor", "kk_math_floor_float"),
                    ("abs", "kk_math_abs_float"),
                    ("exp", "kk_math_exp_float"),
                    ("expm1", "kk_math_expm1_float"),
                    ("ln", "kk_math_ln_float"),
                    ("ln1p", "kk_math_ln1p_float"),
                    ("log2", "kk_math_log2_float"),
                    ("log10", "kk_math_log10_float"),
                    ("log", "kk_math_log_float"),
                    ("sign", "kk_math_sign_float"),
                    ("hypot", "kk_math_hypot_float"),
                ]

                for (name, expectedLink) in floatOverloads {
                    let fq = ["kotlin", "math", name].map { interner.intern($0) }
                    let allSymbols = sema.symbols.lookupAll(fqName: fq)
                    let hasFloatLink = allSymbols.contains { sym in
                        sema.symbols.externalLinkName(for: sym) == expectedLink
                    }
                    #expect(
                        hasFloatLink,
                        "Float overload for \(name) should link to \(expectedLink)"
                    )
                }

            }

            // === testMathTopLevelCallsResolveWithKotlinMathImport ===

            do {

                let sample2Path = paths[2]

                let path = sample2Path

                let sample2Diagnostics = diagnosticsForPath(sample2Path, in: ctx)

                var absCalls: [ExprID] = []
                var callByName: [String: [ExprID]] = [:]

                for exprIndex in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(exprIndex))
                    guard let expr = ast.arena.expr(exprID) else { continue }
                    guard case let .call(calleeExpr, _, _, _) = expr else { continue }
                    guard case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr) else { continue }
                    let name = interner.resolve(calleeName)
                    callByName[name, default: []].append(exprID)
                    if name == "abs" {
                        absCalls.append(exprID)
                    }
                }

                #expect(absCalls.count == 2, "Expected int and double abs calls")

                let expectedOrder: [(String, String)] = [
                    ("abs", "kk_math_abs_int"),
                    ("abs", "kk_math_abs"),
                    ("sqrt", "kk_math_sqrt"),
                    ("pow", "kk_math_pow"),
                    ("ceil", "kk_math_ceil"),
                    ("floor", "kk_math_floor"),
                    ("round", "kk_math_round"),
                ]
                var consumedByName: [String: Int] = [:]

                for (index, expected) in expectedOrder.enumerated() {
                    let (name, expectedLink) = expected
                    let callExpr: ExprID = {
                        if name == "abs" {
                            return absCalls[index == 0 ? 0 : 1]
                        }
                        let selectedIndex = consumedByName[name, default: 0]
                        consumedByName[name] = selectedIndex + 1
                        let candidates = callByName[name] ?? []
                        return candidates[selectedIndex]
                    }()

                    let chosenCallee = try #require(
                        sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                        "Expected chosen callee for \(name)"
                    )
                    #expect(
                        sema.symbols.externalLinkName(for: chosenCallee) == expectedLink,
                        "Expected \(name) to resolve"
                    )
                }

            }

            // === testFloatingPrecisionHelpersResolveWithKotlinMathImport ===

            do {

                let sample3Path = paths[3]

                let path = sample3Path

                let sample3Diagnostics = diagnosticsForPath(sample3Path, in: ctx)

                let expectedLinks = [
                    "kk_double_ulp",
                    "kk_double_nextUp",
                    "kk_double_nextDown",
                    "kk_float_ulp",
                    "kk_float_nextUp",
                    "kk_float_nextDown",
                ]

                var resolvedLinks: [String] = []
                for exprIndex in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(exprIndex))
                    guard let expr = ast.arena.expr(exprID),
                          case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { continue }
                    let name = interner.resolve(calleeName)
                    guard ["ulp", "nextUp", "nextDown"].contains(name),
                          let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                          let link = sema.symbols.externalLinkName(for: chosenCallee)
                    else { continue }
                    resolvedLinks.append(link)
                }

                for expected in expectedLinks {
                    #expect(resolvedLinks.contains(expected), "Expected \(expected) to be resolved")
                }

            }

            // === testMathExtensionPropertySymbolsUseOfficialShape ===

            do {

                let sample4Path = paths[4]

                let sample4Diagnostics = diagnosticsForPath(sample4Path, in: ctx)

                let expected: [(String, TypeID, TypeID, String)] = [
                    ("absoluteValue", sema.types.doubleType, sema.types.doubleType, "kk_math_abs"),
                    ("absoluteValue", sema.types.floatType, sema.types.floatType, "kk_math_abs_float"),
                    ("absoluteValue", sema.types.intType, sema.types.intType, "kk_math_abs_int"),
                    ("absoluteValue", sema.types.longType, sema.types.longType, "kk_math_abs_long"),
                    ("sign", sema.types.doubleType, sema.types.doubleType, "kk_math_sign"),
                    ("sign", sema.types.floatType, sema.types.floatType, "kk_math_sign_float"),
                    ("sign", sema.types.intType, sema.types.intType, "kk_math_sign_int"),
                    ("sign", sema.types.longType, sema.types.intType, "kk_math_sign_long"),
                    ("ulp", sema.types.doubleType, sema.types.doubleType, "kk_double_ulp"),
                    ("ulp", sema.types.floatType, sema.types.floatType, "kk_float_ulp"),
                ]

                for (name, receiverType, returnType, expectedLink) in expected {
                    let symbols = try #require(
                        mathExtensionProperty(named: name, receiverType: receiverType, sema: sema, interner: interner),
                        "Expected \(name) extension property for \(sema.types.renderType(receiverType))"
                    )
                    #expect(sema.symbols.propertyType(for: symbols.property) == returnType)
                    #expect(sema.symbols.externalLinkName(for: symbols.property) == expectedLink)
                    #expect(sema.symbols.externalLinkName(for: symbols.getter) == expectedLink)
                    let getterSignature = try #require(sema.symbols.functionSignature(for: symbols.getter))
                    #expect(getterSignature.receiverType == receiverType)
                    #expect(getterSignature.parameterTypes == [])
                    #expect(getterSignature.returnType == returnType)
                }

            }

            // === testMathExtensionPropertiesResolveWithKotlinMathImport ===

            do {

                let sample5Path = paths[5]

                let path = sample5Path

                let sample5Diagnostics = diagnosticsForPath(sample5Path, in: ctx)

                #expect(!(sample5Diagnostics.contains { $0.severity == .error }), "Expected math extension properties to resolve without diagnostics.")
                let propertyNames: Set<String> = ["absoluteValue", "sign", "ulp"]
                var resolvedLinks: [String] = []
                for exprIndex in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(exprIndex))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, calleeName, _, _, _) = expr,
                          propertyNames.contains(interner.resolve(calleeName)),
                          let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                          let link = sema.symbols.externalLinkName(for: chosenCallee)
                    else {
                        continue
                    }
                    resolvedLinks.append(link)
                }

                for expectedLink in [
                    "kk_math_abs_int",
                    "kk_math_abs_long",
                    "kk_math_abs_float",
                    "kk_math_abs",
                    "kk_math_sign_int",
                    "kk_math_sign_long",
                    "kk_math_sign_float",
                    "kk_math_sign",
                    "kk_float_ulp",
                    "kk_double_ulp",
                ] {
                    #expect(resolvedLinks.contains(expectedLink), "Expected \(expectedLink), got \(resolvedLinks)")
                }

            }

            // === testDoublePowMemberCallResolvesViaMathExtensionStub ===

            do {

                let sample6Path = paths[6]

                let path = sample6Path

                let sample6Diagnostics = diagnosticsForPath(sample6Path, in: ctx)

                #expect(!(sample6Diagnostics.contains { $0.severity == .error }), "Expected Double.pow member call to resolve without diagnostics.")

                let callExpr = try #require(
                    firstExprIDInPath(in: ast, path: sample6Path, ctx: ctx) { _, expr in
                        guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                        return interner.resolve(callee) == "pow"
                    },
                    "Expected pow member call expression"
                )

                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected chosen callee for Double.pow"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == "kk_math_pow"
                )

            }

            // === testRemainingFloatingMathMemberCallsResolveViaDefaultImport ===

            do {

                let sample7Path = paths[7]

                let path = sample7Path

                let sample7Diagnostics = diagnosticsForPath(sample7Path, in: ctx)

                #expect(!(sample7Diagnostics.contains { $0.severity == .error }), "Expected remaining math member calls to resolve without diagnostics.")

                var resolvedLinks: [String] = []
                for exprIndex in ast.arena.exprs.indices {
                    let exprID = ExprID(rawValue: Int32(exprIndex))
                    guard let expr = ast.arena.expr(exprID),
                          case let .memberCall(_, calleeName, _, _, _) = expr,
                          ["IEEErem", "nextTowards", "pow", "withSign"].contains(interner.resolve(calleeName)),
                          let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                          let link = sema.symbols.externalLinkName(for: chosenCallee)
                    else {
                        continue
                    }
                    resolvedLinks.append(link)
                }

                for expectedLink in [
                    "kk_math_IEEErem",
                    "kk_math_IEEErem_float",
                    "kk_math_nextTowards",
                    "kk_math_nextTowards_float",
                    "kk_math_pow_float",
                    "kk_math_pow_int",
                    "kk_math_pow_float_int",
                    "kk_math_withSign",
                    "kk_math_withSign_int",
                    "kk_math_withSign_float",
                    "kk_math_withSign_float_int",
                ] {
                    #expect(resolvedLinks.contains(expectedLink), "Expected \(expectedLink), got \(resolvedLinks)")
                }

            }

        }
    }

}

#endif
