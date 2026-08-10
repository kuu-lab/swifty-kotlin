#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-MATH-001 / STDLIB-MATH-002
// Sema-level overload resolution tests for kotlin.math.
// Verifies that the correct overload is selected for each argument type
// across every overload family, using a single Sema run.
@Suite
struct MathOverloadResolutionTests {

    // MARK: - AST helpers

    private func functionDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard case let .funDecl(function) = ast.arena.decl(declID),
                      interner.resolve(function.name) == name
                else { continue }
                return function
            }
        }
        return nil
    }

    private func bodyRange(of function: FunDecl) -> SourceRange? {
        switch function.body {
        case .block(_, let range), .expr(_, let range):
            return range
        case .unit:
            return nil
        }
    }

    private func firstCallExpr(
        named callName: String,
        in function: FunDecl,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        guard let functionBodyRange = bodyRange(of: function) else { return nil }
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let exprRange = ast.arena.exprRange(exprID),
                  functionBodyRange.contains(exprRange)
            else { continue }

            let matches: Bool
            switch expr {
            case let .call(calleeExpr, _, _, _):
                guard case let .nameRef(callee, _) = ast.arena.expr(calleeExpr) else { continue }
                matches = interner.resolve(callee) == callName
            case let .memberCall(_, callee, _, _, _):
                matches = interner.resolve(callee) == callName
            default:
                continue
            }
            if matches { return exprID }
        }
        return nil
    }

    private func resolvedCallLinks(
        in function: FunDecl,
        ctx: CompilationContext
    ) -> [String] {
        let ast = try! #require(ctx.ast)
        let sema = try! #require(ctx.sema)
        guard let functionBodyRange = bodyRange(of: function) else { return [] }
        var results: [String] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let exprRange = ast.arena.exprRange(exprID),
                  functionBodyRange.contains(exprRange)
            else { continue }

            switch expr {
            case .call, .memberCall:
                break
            default:
                continue
            }
            guard let binding = sema.bindings.callBinding(for: exprID),
                  let link = sema.symbols.externalLinkName(for: binding.chosenCallee)
            else { continue }
            results.append(link)
        }
        return results
    }

    private func resolvedCallCallees(
        in function: FunDecl,
        ctx: CompilationContext
    ) -> [SymbolID] {
        let ast = try! #require(ctx.ast)
        let sema = try! #require(ctx.sema)
        guard let functionBodyRange = bodyRange(of: function) else { return [] }
        var results: [SymbolID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let exprRange = ast.arena.exprRange(exprID),
                  functionBodyRange.contains(exprRange)
            else { continue }

            switch expr {
            case .call, .memberCall:
                break
            default:
                continue
            }
            guard let binding = sema.bindings.callBinding(for: exprID) else { continue }
            results.append(binding.chosenCallee)
        }
        return results
    }

    private func allCallLinks(
        names: Set<String>,
        in function: FunDecl,
        ctx: CompilationContext
    ) -> [String: String] {
        let ast = try! #require(ctx.ast)
        let sema = try! #require(ctx.sema)
        let interner = ctx.interner
        guard let functionBodyRange = bodyRange(of: function) else { return [:] }
        var results: [String: String] = [:]
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  let exprRange = ast.arena.exprRange(exprID),
                  functionBodyRange.contains(exprRange)
            else { continue }

            let name: String?
            switch expr {
            case let .call(calleeExpr, _, _, _):
                guard case let .nameRef(callee, _) = ast.arena.expr(calleeExpr) else { continue }
                name = interner.resolve(callee)
            case let .memberCall(_, callee, _, _, _):
                name = interner.resolve(callee)
            default:
                continue
            }
            guard let name, names.contains(name), results[name] == nil,
                  let binding = sema.bindings.callBinding(for: exprID),
                  let link = sema.symbols.externalLinkName(for: binding.chosenCallee)
            else { continue }
            results[name] = link
        }
        return results
    }

    private func assertLink(
        forCall callName: String,
        inFunction functionName: String,
        expected: String,
        ctx: CompilationContext
    ) throws {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let function = try #require(
            functionDecl(named: functionName, in: ast, interner: interner),
            "Missing function \(functionName)"
        )
        let exprID = try #require(
            firstCallExpr(named: callName, in: function, ast: ast, interner: interner),
            "Missing \(callName) call in \(functionName)"
        )
        let chosenCallee = try #require(
            sema.bindings.callBinding(for: exprID)?.chosenCallee,
            "No call binding for \(callName) in \(functionName)"
        )
        let link = try #require(
            sema.symbols.externalLinkName(for: chosenCallee),
            "No external link resolved for \(callName) in \(functionName)"
        )
        #expect(link == expected, "\(functionName).\(callName) should resolve to \(expected), got \(link)")
    }

    private func assertSourceBackedSignature(
        forCall callName: String,
        inFunction functionName: String,
        expected: String,
        ctx: CompilationContext
    ) throws {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner
        let function = try #require(
            functionDecl(named: functionName, in: ast, interner: interner),
            "Missing function \(functionName)"
        )
        let exprID = try #require(
            firstCallExpr(named: callName, in: function, ast: ast, interner: interner),
            "Missing \(callName) call in \(functionName)"
        )
        let chosenCallee = try #require(
            sema.bindings.callBinding(for: exprID)?.chosenCallee,
            "No call binding for \(callName) in \(functionName)"
        )
        #expect(
            sema.symbols.externalLinkName(for: chosenCallee) == nil,
            "\(functionName).\(callName) must resolve to bundled Kotlin source"
        )
        let signature = try #require(sema.symbols.functionSignature(for: chosenCallee))
        let parameters = signature.parameterTypes.map { sema.types.renderType($0) }.joined(separator: ", ")
        let rendered = "(\(parameters)) -> \(sema.types.renderType(signature.returnType))"
        #expect(rendered == expected, "\(functionName).\(callName) resolved to \(rendered), expected \(expected)")
    }

    // MARK: - Consolidated math overload resolution

    @Test func testMathOverloadsResolveToExpectedRuntimeLinks() throws {
        let source = """
        import kotlin.math.*

        fun absInt(x: Int): Int = abs(x)
        fun absLong(x: Long): Long = abs(x)
        fun absDouble(x: Double): Double = abs(x)
        fun absFloat(x: Float): Float = abs(x)

        fun sqrtDouble(x: Double): Double = sqrt(x)
        fun sqrtFloat(x: Float): Float = sqrt(x)

        fun powDouble(x: Double, y: Double): Double = pow(x, y)
        fun powFloat(x: Float, y: Float): Float = pow(x, y)
        fun powDoubleInt(x: Double, n: Int): Double = pow(x, n)
        fun powFloatInt(x: Float, n: Int): Float = pow(x, n)

        fun ieeeRemDouble(x: Double, y: Double): Double = x.IEEErem(y)
        fun ieeeRemFloat(x: Float, y: Float): Float = x.IEEErem(y)
        fun nextTowardsDouble(x: Double, y: Double): Double = x.nextTowards(y)
        fun nextTowardsFloat(x: Float, y: Float): Float = x.nextTowards(y)
        fun withSignDoubleDouble(x: Double, y: Double): Double = x.withSign(y)
        fun withSignDoubleInt(x: Double, sign: Int): Double = x.withSign(sign)
        fun withSignFloatFloat(x: Float, y: Float): Float = x.withSign(y)
        fun withSignFloatInt(x: Float, sign: Int): Float = x.withSign(sign)

        fun roundDouble(x: Double): Double = round(x)
        fun roundFloat(x: Float): Float = round(x)
        fun ceilDouble(x: Double): Double = ceil(x)
        fun ceilFloat(x: Float): Float = ceil(x)
        fun floorDouble(x: Double): Double = floor(x)
        fun floorFloat(x: Float): Float = floor(x)

        fun trigDouble(x: Double): Double {
            val a = sin(x)
            val b = cos(x)
            val c = tan(x)
            val d = asin(x)
            val e = acos(x)
            val f = atan(x)
            return a + b + c + d + e + f
        }

        fun trigFloat(x: Float): Float {
            val a = sin(x)
            val b = cos(x)
            val c = tan(x)
            val d = asin(x)
            val e = acos(x)
            val f = atan(x)
            return a + b + c + d + e + f
        }

        fun atan2Double(y: Double, x: Double): Double = atan2(y, x)
        fun atan2Float(y: Float, x: Float): Float = atan2(y, x)

        fun hyperbolicDouble(x: Double): Double {
            val a = sinh(x)
            val b = cosh(x)
            val c = tanh(x)
            return a + b + c
        }

        fun hyperbolicFloat(x: Float): Float {
            val a = sinh(x)
            val b = cosh(x)
            val c = tanh(x)
            return a + b + c
        }

        fun inverseHyperbolicDouble(x: Double): Double {
            val a = acosh(x)
            val b = asinh(x)
            val c = atanh(x)
            return a + b + c
        }

        fun inverseHyperbolicFloat(x: Float): Float {
            val a = acosh(x)
            val b = asinh(x)
            val c = atanh(x)
            return a + b + c
        }

        fun logExpDouble(x: Double): Double {
            val a = exp(x)
            val b = ln(x)
            val c = log2(x)
            val d = log10(x)
            val e = expm1(x)
            val f = ln1p(x)
            return a + b + c + d + e + f
        }

        fun logExpFloat(x: Float): Float {
            val a = exp(x)
            val b = ln(x)
            val c = log2(x)
            val d = log10(x)
            val e = expm1(x)
            val f = ln1p(x)
            return a + b + c + d + e + f
        }

        fun logTwoArgDouble(x: Double, base: Double): Double = log(x, base)
        fun logTwoArgFloat(x: Float, base: Float): Float = log(x, base)

        fun hypotDouble(x: Double, y: Double): Double = hypot(x, y)
        fun hypotFloat(x: Float, y: Float): Float = hypot(x, y)

        fun maxDouble(a: Double, b: Double): Double = max(a, b)
        fun maxFloat(a: Float, b: Float): Float = max(a, b)
        fun maxInt(a: Int, b: Int): Int = max(a, b)
        fun maxLong(a: Long, b: Long): Long = max(a, b)
        fun maxUInt(a: UInt, b: UInt): UInt = max(a, b)
        fun maxULong(a: ULong, b: ULong): ULong = max(a, b)

        fun minDouble(a: Double, b: Double): Double = min(a, b)
        fun minFloat(a: Float, b: Float): Float = min(a, b)
        fun minInt(a: Int, b: Int): Int = min(a, b)
        fun minLong(a: Long, b: Long): Long = min(a, b)
        fun minUInt(a: UInt, b: UInt): UInt = min(a, b)
        fun minULong(a: ULong, b: ULong): ULong = min(a, b)

        fun cbrtDouble(x: Double): Double = cbrt(x)
        fun cbrtFloat(x: Float): Float = cbrt(x)

        fun signDouble(x: Double): Double = sign(x)
        fun signFloat(x: Float): Float = sign(x)

        fun truncateDouble(x: Double): Double = truncate(x)
        fun truncateFloat(x: Float): Float = truncate(x)

        fun roundToIntDouble(x: Double): Int = roundToInt(x)
        fun roundToIntFloat(x: Float): Int = roundToInt(x)
        fun roundToLongDouble(x: Double): Long = roundToLong(x)
        fun roundToLongFloat(x: Float): Long = roundToLong(x)

        fun fqnAbsInt(x: Int): Int = kotlin.math.abs(x)
        fun fqnAbsDouble(x: Double): Double = kotlin.math.abs(x)
        fun fqnSqrtDouble(x: Double): Double = kotlin.math.sqrt(x)

        fun absDistinct(i: Int, l: Long, d: Double, flt: Float) {
            val ai = abs(i)
            val al = abs(l)
            val ad = abs(d)
            val af = abs(flt)
        }

        fun sqrtDistinct(d: Double, flt: Float) {
            val sd = sqrt(d)
            val sf = sqrt(flt)
        }

        // Negative cases: these should produce diagnostics but must not break
        // resolution of the positive cases above.
        fun memberOnlyTopLevel(d: Double, f: Float, i: Int) {
            IEEErem(d, d)
            IEEErem(f, f)
            nextTowards(d, d)
            nextTowards(f, f)
            withSign(d, d)
            withSign(d, i)
            withSign(f, f)
            withSign(f, i)
        }

        fun unofficialRounding(x: Double) {
            roundUp(x)
            roundDown(x)
            roundHalfEven(x)
        }
        """

        let ctx = makeContextFromSource(source)
        do { try runSema(ctx) } catch { }

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        // Positive overload assertions
        try assertSourceBackedSignature(forCall: "abs", inFunction: "absInt", expected: "(Int) -> Int", ctx: ctx)
        try assertSourceBackedSignature(forCall: "abs", inFunction: "absLong", expected: "(Long) -> Long", ctx: ctx)
        try assertSourceBackedSignature(forCall: "abs", inFunction: "absDouble", expected: "(Double) -> Double", ctx: ctx)
        try assertSourceBackedSignature(forCall: "abs", inFunction: "absFloat", expected: "(Float) -> Float", ctx: ctx)

        try assertLink(forCall: "sqrt", inFunction: "sqrtDouble", expected: "kk_math_sqrt", ctx: ctx)
        try assertLink(forCall: "sqrt", inFunction: "sqrtFloat", expected: "kk_math_sqrt_float", ctx: ctx)

        try assertLink(forCall: "pow", inFunction: "powDouble", expected: "kk_math_pow", ctx: ctx)
        try assertLink(forCall: "pow", inFunction: "powFloat", expected: "kk_math_pow_float", ctx: ctx)
        try assertLink(forCall: "pow", inFunction: "powDoubleInt", expected: "kk_math_pow_int", ctx: ctx)
        try assertLink(forCall: "pow", inFunction: "powFloatInt", expected: "kk_math_pow_float_int", ctx: ctx)

        try assertLink(forCall: "IEEErem", inFunction: "ieeeRemDouble", expected: "kk_math_IEEErem", ctx: ctx)
        try assertLink(forCall: "IEEErem", inFunction: "ieeeRemFloat", expected: "kk_math_IEEErem_float", ctx: ctx)
        try assertLink(forCall: "nextTowards", inFunction: "nextTowardsDouble", expected: "kk_math_nextTowards", ctx: ctx)
        try assertLink(forCall: "nextTowards", inFunction: "nextTowardsFloat", expected: "kk_math_nextTowards_float", ctx: ctx)
        try assertLink(forCall: "withSign", inFunction: "withSignDoubleDouble", expected: "kk_math_withSign", ctx: ctx)
        try assertLink(forCall: "withSign", inFunction: "withSignDoubleInt", expected: "kk_math_withSign_int", ctx: ctx)
        try assertLink(forCall: "withSign", inFunction: "withSignFloatFloat", expected: "kk_math_withSign_float", ctx: ctx)
        try assertLink(forCall: "withSign", inFunction: "withSignFloatInt", expected: "kk_math_withSign_float_int", ctx: ctx)

        try assertLink(forCall: "round", inFunction: "roundDouble", expected: "kk_math_round", ctx: ctx)
        try assertLink(forCall: "round", inFunction: "roundFloat", expected: "kk_math_round_float", ctx: ctx)
        try assertLink(forCall: "ceil", inFunction: "ceilDouble", expected: "kk_math_ceil", ctx: ctx)
        try assertLink(forCall: "ceil", inFunction: "ceilFloat", expected: "kk_math_ceil_float", ctx: ctx)
        try assertLink(forCall: "floor", inFunction: "floorDouble", expected: "kk_math_floor", ctx: ctx)
        try assertLink(forCall: "floor", inFunction: "floorFloat", expected: "kk_math_floor_float", ctx: ctx)

        let trigDoubleFunction = try #require(functionDecl(named: "trigDouble", in: ast, interner: interner))
        let trigDoubleLinks = allCallLinks(names: ["sin", "cos", "tan", "asin", "acos", "atan"], in: trigDoubleFunction, ctx: ctx)
        #expect(trigDoubleLinks["sin"] == "kk_math_sin")
        #expect(trigDoubleLinks["cos"] == "kk_math_cos")
        #expect(trigDoubleLinks["tan"] == "kk_math_tan")
        #expect(trigDoubleLinks["asin"] == "kk_math_asin")
        #expect(trigDoubleLinks["acos"] == "kk_math_acos")
        #expect(trigDoubleLinks["atan"] == "kk_math_atan")

        let trigFloatFunction = try #require(functionDecl(named: "trigFloat", in: ast, interner: interner))
        let trigFloatLinks = allCallLinks(names: ["sin", "cos", "tan", "asin", "acos", "atan"], in: trigFloatFunction, ctx: ctx)
        #expect(trigFloatLinks["sin"] == "kk_math_sin_float")
        #expect(trigFloatLinks["cos"] == "kk_math_cos_float")
        #expect(trigFloatLinks["tan"] == "kk_math_tan_float")
        #expect(trigFloatLinks["asin"] == "kk_math_asin_float")
        #expect(trigFloatLinks["acos"] == "kk_math_acos_float")
        #expect(trigFloatLinks["atan"] == "kk_math_atan_float")

        try assertLink(forCall: "atan2", inFunction: "atan2Double", expected: "kk_math_atan2", ctx: ctx)
        try assertLink(forCall: "atan2", inFunction: "atan2Float", expected: "kk_math_atan2_float", ctx: ctx)

        let hyperbolicDoubleFunction = try #require(functionDecl(named: "hyperbolicDouble", in: ast, interner: interner))
        let hyperbolicDoubleLinks = allCallLinks(names: ["sinh", "cosh", "tanh"], in: hyperbolicDoubleFunction, ctx: ctx)
        #expect(hyperbolicDoubleLinks["sinh"] == "kk_math_sinh")
        #expect(hyperbolicDoubleLinks["cosh"] == "kk_math_cosh")
        #expect(hyperbolicDoubleLinks["tanh"] == "kk_math_tanh")

        let hyperbolicFloatFunction = try #require(functionDecl(named: "hyperbolicFloat", in: ast, interner: interner))
        let hyperbolicFloatLinks = allCallLinks(names: ["sinh", "cosh", "tanh"], in: hyperbolicFloatFunction, ctx: ctx)
        #expect(hyperbolicFloatLinks["sinh"] == "kk_math_sinh_float")
        #expect(hyperbolicFloatLinks["cosh"] == "kk_math_cosh_float")
        #expect(hyperbolicFloatLinks["tanh"] == "kk_math_tanh_float")

        let inverseHyperbolicDoubleFunction = try #require(functionDecl(named: "inverseHyperbolicDouble", in: ast, interner: interner))
        let inverseHyperbolicDoubleLinks = allCallLinks(names: ["acosh", "asinh", "atanh"], in: inverseHyperbolicDoubleFunction, ctx: ctx)
        #expect(inverseHyperbolicDoubleLinks["acosh"] == "kk_math_acosh")
        #expect(inverseHyperbolicDoubleLinks["asinh"] == "kk_math_asinh")
        #expect(inverseHyperbolicDoubleLinks["atanh"] == "kk_math_atanh")

        let inverseHyperbolicFloatFunction = try #require(functionDecl(named: "inverseHyperbolicFloat", in: ast, interner: interner))
        let inverseHyperbolicFloatLinks = allCallLinks(names: ["acosh", "asinh", "atanh"], in: inverseHyperbolicFloatFunction, ctx: ctx)
        #expect(inverseHyperbolicFloatLinks["acosh"] == "kk_math_acosh_float")
        #expect(inverseHyperbolicFloatLinks["asinh"] == "kk_math_asinh_float")
        #expect(inverseHyperbolicFloatLinks["atanh"] == "kk_math_atanh_float")

        let logExpDoubleFunction = try #require(functionDecl(named: "logExpDouble", in: ast, interner: interner))
        let logExpDoubleLinks = allCallLinks(names: ["exp", "ln", "log2", "log10", "expm1", "ln1p"], in: logExpDoubleFunction, ctx: ctx)
        #expect(logExpDoubleLinks["exp"] == "kk_math_exp")
        #expect(logExpDoubleLinks["ln"] == "kk_math_ln")
        #expect(logExpDoubleLinks["log2"] == "kk_math_log2")
        #expect(logExpDoubleLinks["log10"] == "kk_math_log10")
        #expect(logExpDoubleLinks["expm1"] == "kk_math_expm1")
        #expect(logExpDoubleLinks["ln1p"] == "kk_math_ln1p")

        let logExpFloatFunction = try #require(functionDecl(named: "logExpFloat", in: ast, interner: interner))
        let logExpFloatLinks = allCallLinks(names: ["exp", "ln", "log2", "log10", "expm1", "ln1p"], in: logExpFloatFunction, ctx: ctx)
        #expect(logExpFloatLinks["exp"] == "kk_math_exp_float")
        #expect(logExpFloatLinks["ln"] == "kk_math_ln_float")
        #expect(logExpFloatLinks["log2"] == "kk_math_log2_float")
        #expect(logExpFloatLinks["log10"] == "kk_math_log10_float")
        #expect(logExpFloatLinks["expm1"] == "kk_math_expm1_float")
        #expect(logExpFloatLinks["ln1p"] == "kk_math_ln1p_float")

        try assertLink(forCall: "log", inFunction: "logTwoArgDouble", expected: "kk_math_log", ctx: ctx)
        try assertLink(forCall: "log", inFunction: "logTwoArgFloat", expected: "kk_math_log_float", ctx: ctx)

        try assertLink(forCall: "hypot", inFunction: "hypotDouble", expected: "kk_math_hypot", ctx: ctx)
        try assertLink(forCall: "hypot", inFunction: "hypotFloat", expected: "kk_math_hypot_float", ctx: ctx)

        for name in ["max", "min"] {
            for type in ["Double", "Float", "Int", "Long", "UInt", "ULong"] {
                let functionName = name + type
                try assertSourceBackedSignature(
                    forCall: name,
                    inFunction: functionName,
                    expected: "(\(type), \(type)) -> \(type)",
                    ctx: ctx
                )
            }
        }

        try assertLink(forCall: "cbrt", inFunction: "cbrtDouble", expected: "kk_math_cbrt", ctx: ctx)
        try assertLink(forCall: "cbrt", inFunction: "cbrtFloat", expected: "kk_math_cbrt_float", ctx: ctx)

        try assertSourceBackedSignature(forCall: "sign", inFunction: "signDouble", expected: "(Double) -> Double", ctx: ctx)
        try assertSourceBackedSignature(forCall: "sign", inFunction: "signFloat", expected: "(Float) -> Float", ctx: ctx)

        try assertLink(forCall: "truncate", inFunction: "truncateDouble", expected: "kk_math_truncate", ctx: ctx)
        try assertLink(forCall: "truncate", inFunction: "truncateFloat", expected: "kk_math_truncate_float", ctx: ctx)

        try assertLink(forCall: "roundToInt", inFunction: "roundToIntDouble", expected: "kk_double_roundToInt", ctx: ctx)
        try assertLink(forCall: "roundToInt", inFunction: "roundToIntFloat", expected: "kk_float_roundToInt", ctx: ctx)
        try assertLink(forCall: "roundToLong", inFunction: "roundToLongDouble", expected: "kk_double_roundToLong", ctx: ctx)
        try assertLink(forCall: "roundToLong", inFunction: "roundToLongFloat", expected: "kk_float_roundToLong", ctx: ctx)

        try assertSourceBackedSignature(forCall: "abs", inFunction: "fqnAbsInt", expected: "(Int) -> Int", ctx: ctx)
        try assertSourceBackedSignature(forCall: "abs", inFunction: "fqnAbsDouble", expected: "(Double) -> Double", ctx: ctx)
        try assertLink(forCall: "sqrt", inFunction: "fqnSqrtDouble", expected: "kk_math_sqrt", ctx: ctx)

        // Distinct overload sets
        let absDistinctFunction = try #require(functionDecl(named: "absDistinct", in: ast, interner: interner))
        let absDistinctCallees = resolvedCallCallees(in: absDistinctFunction, ctx: ctx)
        #expect(absDistinctCallees.count == 4, "Expected one chosen callee per abs call")
        #expect(Set(absDistinctCallees).count == 4, "Each abs overload should resolve to a different declaration")

        let sqrtDistinctFunction = try #require(functionDecl(named: "sqrtDistinct", in: ast, interner: interner))
        let sqrtDistinctLinks = resolvedCallLinks(in: sqrtDistinctFunction, ctx: ctx)
        #expect(Set(sqrtDistinctLinks).isSuperset(of: [
            "kk_math_sqrt",
            "kk_math_sqrt_float",
        ]))

        // Negative cases: there should be diagnostics, and the invalid calls must not resolve.
        #expect(ctx.diagnostics.hasError, "Expected unresolved member-only and unofficial math calls to produce errors")
        let hasSemaDiagnostic = ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") }
        #expect(hasSemaDiagnostic, "Expected KSWIFTK-SEMA diagnostics for invalid math calls")

        let memberOnlyFunction = try #require(functionDecl(named: "memberOnlyTopLevel", in: ast, interner: interner))
        let unofficialFunction = try #require(functionDecl(named: "unofficialRounding", in: ast, interner: interner))

        for invalidCall in ["IEEErem", "nextTowards", "withSign"] {
            let exprID = firstCallExpr(named: invalidCall, in: memberOnlyFunction, ast: ast, interner: interner)
            #expect(exprID != nil, "Expected top-level \(invalidCall) call in memberOnlyTopLevel")
            if let exprID {
                #expect(sema.bindings.callBinding(for: exprID) == nil, "Top-level \(invalidCall) should not resolve")
            }
        }
        for invalidCall in ["roundUp", "roundDown", "roundHalfEven"] {
            let exprID = firstCallExpr(named: invalidCall, in: unofficialFunction, ast: ast, interner: interner)
            #expect(exprID != nil, "Expected \(invalidCall) call in unofficialRounding")
            if let exprID {
                #expect(sema.bindings.callBinding(for: exprID) == nil, "\(invalidCall) should not resolve from kotlin.math")
            }
        }
    }
}
#endif
