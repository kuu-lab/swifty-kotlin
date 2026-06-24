#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// STDLIB-MATH-001 / STDLIB-MATH-002
// Sema-level overload resolution tests for kotlin.math.
// Verifies that the correct overload is selected for each argument type
// (Double, Float, Int, Long) across every overload family.
// No runtime edits; these tests only exercise the sema pipeline.

@Suite
struct MathOverloadResolutionTests {

    // MARK: - Helpers

    /// Kotlin does not default-import `kotlin.math`; tests must opt in explicitly.
    private func withKotlinMathImport(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("import kotlin.math") {
            return source
        }
        return "import kotlin.math.*\n\n" + source
    }

    private func resolvedLink(
        forCall callName: String,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String? {
        var result: String?
        try withTemporaryFile(contents: withKotlinMathImport(source)) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Unexpected sema error for '\(callName)'")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID) else { continue }
                let matchesCallName: Bool
                switch expr {
                case let .call(calleeExpr, _, _, _):
                    guard case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr) else {
                        continue
                    }
                    matchesCallName = ctx.interner.resolve(calleeName) == callName
                case let .memberCall(_, calleeName, _, _, _):
                    matchesCallName = ctx.interner.resolve(calleeName) == callName
                default:
                    continue
                }
                guard matchesCallName else { continue }
                if let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee {
                    result = sema.symbols.externalLinkName(for: chosenCallee)
                }
                break
            }
        }
        return result
    }

    private func resolvedLinkForFirstMatchingCall(
        names: Set<String>,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: String] {
        var results: [String: String] = [:]
        try withTemporaryFile(contents: withKotlinMathImport(source)) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError), "Unexpected sema error")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID) else { continue }
                guard case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                else { continue }
                let name = ctx.interner.resolve(calleeName)
                guard names.contains(name), results[name] == nil else { continue }
                if let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee {
                    if let link = sema.symbols.externalLinkName(for: chosenCallee) {
                        results[name] = link
                    }
                }
            }
        }
        return results
    }

    // MARK: - abs family (Int / Long / Double / Float)

    @Test func testAbsIntOverload() throws {
        let source = "fun f(x: Int): Int = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        #expect(link == "kk_math_abs_int")
    }

    @Test func testAbsLongOverload() throws {
        let source = "fun f(x: Long): Long = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        #expect(link == "kk_math_abs_long")
    }

    @Test func testAbsDoubleOverload() throws {
        let source = "fun f(x: Double): Double = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        #expect(link == "kk_math_abs")
    }

    @Test func testAbsFloatOverload() throws {
        let source = "fun f(x: Float): Float = abs(x)"
        let link = try resolvedLink(forCall: "abs", withSource: source)
        #expect(link == "kk_math_abs_float")
    }

    // MARK: - sqrt family (Double / Float)

    @Test func testSqrtDoubleOverload() throws {
        let source = "fun f(x: Double): Double = sqrt(x)"
        let link = try resolvedLink(forCall: "sqrt", withSource: source)
        #expect(link == "kk_math_sqrt")
    }

    @Test func testSqrtFloatOverload() throws {
        let source = "fun f(x: Float): Float = sqrt(x)"
        let link = try resolvedLink(forCall: "sqrt", withSource: source)
        #expect(link == "kk_math_sqrt_float")
    }

    // MARK: - pow family (Double / Float, floating and Int exponents)

    @Test func testPowDoubleOverload() throws {
        let source = "fun f(x: Double, y: Double): Double = pow(x, y)"
        let link = try resolvedLink(forCall: "pow", withSource: source)
        #expect(link == "kk_math_pow")
    }

    @Test func testPowRemainingOverloads() throws {
        let cases: [(source: String, expectedLink: String)] = [
            ("fun f(x: Float, y: Float): Float = pow(x, y)", "kk_math_pow_float"),
            ("fun f(x: Double, n: Int): Double = pow(x, n)", "kk_math_pow_int"),
            ("fun f(x: Float, n: Int): Float = pow(x, n)", "kk_math_pow_float_int"),
        ]

        for testCase in cases {
            let link = try resolvedLink(forCall: "pow", withSource: testCase.source)
            #expect(link == testCase.expectedLink)
        }
    }

    @Test func testIEEEremNextTowardsAndWithSignOverloads() throws {
        let cases: [(name: String, source: String, expectedLink: String)] = [
            ("IEEErem", "fun f(x: Double, y: Double): Double = x.IEEErem(y)", "kk_math_IEEErem"),
            ("IEEErem", "fun f(x: Float, y: Float): Float = x.IEEErem(y)", "kk_math_IEEErem_float"),
            ("nextTowards", "fun f(x: Double, y: Double): Double = x.nextTowards(y)", "kk_math_nextTowards"),
            ("nextTowards", "fun f(x: Float, y: Float): Float = x.nextTowards(y)", "kk_math_nextTowards_float"),
            ("withSign", "fun f(x: Double, y: Double): Double = x.withSign(y)", "kk_math_withSign"),
            ("withSign", "fun f(x: Double, sign: Int): Double = x.withSign(sign)", "kk_math_withSign_int"),
            ("withSign", "fun f(x: Float, y: Float): Float = x.withSign(y)", "kk_math_withSign_float"),
            ("withSign", "fun f(x: Float, sign: Int): Float = x.withSign(sign)", "kk_math_withSign_float_int"),
        ]

        for testCase in cases {
            let link = try resolvedLink(forCall: testCase.name, withSource: testCase.source)
            #expect(link == testCase.expectedLink)
        }
    }

    @Test func testFloatingMemberOnlyMathFunctionsRejectTopLevelCalls() throws {
        let source = """
        import kotlin.math.*

        fun sample(d: Double, f: Float, i: Int) {
            IEEErem(d, d)
            IEEErem(f, f)
            nextTowards(d, d)
            nextTowards(f, f)
            withSign(d, d)
            withSign(d, i)
            withSign(f, f)
            withSign(f, i)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected member-only math helpers to reject top-level calls.")
        }
    }

    // MARK: - round / ceil / floor family (Double / Float)

    @Test func testRoundDoubleOverload() throws {
        let source = "fun f(x: Double): Double = round(x)"
        let link = try resolvedLink(forCall: "round", withSource: source)
        #expect(link == "kk_math_round")
    }

    @Test func testRoundFloatOverload() throws {
        let source = "fun f(x: Float): Float = round(x)"
        let link = try resolvedLink(forCall: "round", withSource: source)
        #expect(link == "kk_math_round_float")
    }

    @Test func testCeilDoubleOverload() throws {
        let source = "fun f(x: Double): Double = ceil(x)"
        let link = try resolvedLink(forCall: "ceil", withSource: source)
        #expect(link == "kk_math_ceil")
    }

    @Test func testCeilFloatOverload() throws {
        let source = "fun f(x: Float): Float = ceil(x)"
        let link = try resolvedLink(forCall: "ceil", withSource: source)
        #expect(link == "kk_math_ceil_float")
    }

    @Test func testFloorDoubleOverload() throws {
        let source = "fun f(x: Double): Double = floor(x)"
        let link = try resolvedLink(forCall: "floor", withSource: source)
        #expect(link == "kk_math_floor")
    }

    @Test func testFloorFloatOverload() throws {
        let source = "fun f(x: Float): Float = floor(x)"
        let link = try resolvedLink(forCall: "floor", withSource: source)
        #expect(link == "kk_math_floor_float")
    }

    // MARK: - Trig family (Double / Float): sin / cos / tan / asin / acos / atan

    @Test func testTrigDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = sin(x)
            val b = cos(x)
            val c = tan(x)
            val d = asin(x)
            val e = acos(x)
            val f = atan(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sin", "cos", "tan", "asin", "acos", "atan"],
            withSource: source
        )
        #expect(links["sin"] == "kk_math_sin")
        #expect(links["cos"] == "kk_math_cos")
        #expect(links["tan"] == "kk_math_tan")
        #expect(links["asin"] == "kk_math_asin")
        #expect(links["acos"] == "kk_math_acos")
        #expect(links["atan"] == "kk_math_atan")
    }

    @Test func testTrigFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = sin(x)
            val b = cos(x)
            val c = tan(x)
            val d = asin(x)
            val e = acos(x)
            val f = atan(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sin", "cos", "tan", "asin", "acos", "atan"],
            withSource: source
        )
        #expect(links["sin"] == "kk_math_sin_float")
        #expect(links["cos"] == "kk_math_cos_float")
        #expect(links["tan"] == "kk_math_tan_float")
        #expect(links["asin"] == "kk_math_asin_float")
        #expect(links["acos"] == "kk_math_acos_float")
        #expect(links["atan"] == "kk_math_atan_float")
    }

    // MARK: - atan2 family (Double / Float)

    @Test func testAtan2DoubleOverload() throws {
        let source = "fun f(y: Double, x: Double): Double = atan2(y, x)"
        let link = try resolvedLink(forCall: "atan2", withSource: source)
        #expect(link == "kk_math_atan2")
    }

    @Test func testAtan2FloatOverload() throws {
        let source = "fun f(y: Float, x: Float): Float = atan2(y, x)"
        let link = try resolvedLink(forCall: "atan2", withSource: source)
        #expect(link == "kk_math_atan2_float")
    }

    // MARK: - Hyperbolic family (Double / Float): sinh / cosh / tanh

    @Test func testHyperbolicDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = sinh(x)
            val b = cosh(x)
            val c = tanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sinh", "cosh", "tanh"],
            withSource: source
        )
        #expect(links["sinh"] == "kk_math_sinh")
        #expect(links["cosh"] == "kk_math_cosh")
        #expect(links["tanh"] == "kk_math_tanh")
    }

    @Test func testHyperbolicFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = sinh(x)
            val b = cosh(x)
            val c = tanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["sinh", "cosh", "tanh"],
            withSource: source
        )
        #expect(links["sinh"] == "kk_math_sinh_float")
        #expect(links["cosh"] == "kk_math_cosh_float")
        #expect(links["tanh"] == "kk_math_tanh_float")
    }

    // MARK: - Inverse hyperbolic family (Double / Float): acosh / asinh / atanh

    @Test func testInverseHyperbolicDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = acosh(x)
            val b = asinh(x)
            val c = atanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["acosh", "asinh", "atanh"],
            withSource: source
        )
        #expect(links["acosh"] == "kk_math_acosh")
        #expect(links["asinh"] == "kk_math_asinh")
        #expect(links["atanh"] == "kk_math_atanh")
    }

    @Test func testInverseHyperbolicFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = acosh(x)
            val b = asinh(x)
            val c = atanh(x)
            return a + b + c
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["acosh", "asinh", "atanh"],
            withSource: source
        )
        #expect(links["acosh"] == "kk_math_acosh_float")
        #expect(links["asinh"] == "kk_math_asinh_float")
        #expect(links["atanh"] == "kk_math_atanh_float")
    }

    // MARK: - log / exp family (Double / Float)

    @Test func testLogExpDoubleFamilyOverloads() throws {
        let source = """
        fun f(x: Double): Double {
            val a = exp(x)
            val b = ln(x)
            val c = log2(x)
            val d = log10(x)
            val e = expm1(x)
            val f = ln1p(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["exp", "ln", "log2", "log10", "expm1", "ln1p"],
            withSource: source
        )
        #expect(links["exp"] == "kk_math_exp")
        #expect(links["ln"] == "kk_math_ln")
        #expect(links["log2"] == "kk_math_log2")
        #expect(links["log10"] == "kk_math_log10")
        #expect(links["expm1"] == "kk_math_expm1")
        #expect(links["ln1p"] == "kk_math_ln1p")
    }

    @Test func testLogExpFloatFamilyOverloads() throws {
        let source = """
        fun f(x: Float): Float {
            val a = exp(x)
            val b = ln(x)
            val c = log2(x)
            val d = log10(x)
            val e = expm1(x)
            val f = ln1p(x)
            return a + b + c + d + e + f
        }
        """
        let links = try resolvedLinkForFirstMatchingCall(
            names: ["exp", "ln", "log2", "log10", "expm1", "ln1p"],
            withSource: source
        )
        #expect(links["exp"] == "kk_math_exp_float")
        #expect(links["ln"] == "kk_math_ln_float")
        #expect(links["log2"] == "kk_math_log2_float")
        #expect(links["log10"] == "kk_math_log10_float")
        #expect(links["expm1"] == "kk_math_expm1_float")
        #expect(links["ln1p"] == "kk_math_ln1p_float")
    }

    @Test func testLogTwoArgDoubleOverload() throws {
        let source = "fun f(x: Double, base: Double): Double = log(x, base)"
        let link = try resolvedLink(forCall: "log", withSource: source)
        #expect(link == "kk_math_log")
    }

    @Test func testLogTwoArgFloatOverload() throws {
        let source = "fun f(x: Float, base: Float): Float = log(x, base)"
        let link = try resolvedLink(forCall: "log", withSource: source)
        #expect(link == "kk_math_log_float")
    }

    // MARK: - hypot family (Double / Float)

    @Test func testHypotDoubleOverload() throws {
        let source = "fun f(x: Double, y: Double): Double = hypot(x, y)"
        let link = try resolvedLink(forCall: "hypot", withSource: source)
        #expect(link == "kk_math_hypot")
    }

    @Test func testHypotFloatOverload() throws {
        let source = "fun f(x: Float, y: Float): Float = hypot(x, y)"
        let link = try resolvedLink(forCall: "hypot", withSource: source)
        #expect(link == "kk_math_hypot_float")
    }

    // MARK: - min / max family (Double / Float / Int / Long / UInt / ULong)

    @Test func testMinMaxOverloadMatrix() throws {
        let cases: [(name: String, type: String, expectedLink: String)] = [
            ("max", "Double", "kk_math_max"),
            ("max", "Float", "kk_math_max_float"),
            ("max", "Int", "kk_math_max_int"),
            ("max", "Long", "kk_math_max_long"),
            ("max", "UInt", "kk_math_max_uint"),
            ("max", "ULong", "kk_math_max_ulong"),
            ("min", "Double", "kk_math_min"),
            ("min", "Float", "kk_math_min_float"),
            ("min", "Int", "kk_math_min_int"),
            ("min", "Long", "kk_math_min_long"),
            ("min", "UInt", "kk_math_min_uint"),
            ("min", "ULong", "kk_math_min_ulong"),
        ]

        for testCase in cases {
            let source = "fun f(a: \(testCase.type), b: \(testCase.type)): \(testCase.type) = \(testCase.name)(a, b)"
            let link = try resolvedLink(forCall: testCase.name, withSource: source)
            #expect(
                link == testCase.expectedLink,
                "\(testCase.name)(\(testCase.type), \(testCase.type)) should resolve to \(testCase.expectedLink)"
            )
        }
    }

    // MARK: - cbrt family (Double / Float)

    @Test func testCbrtDoubleOverload() throws {
        let source = "fun f(x: Double): Double = cbrt(x)"
        let link = try resolvedLink(forCall: "cbrt", withSource: source)
        #expect(link == "kk_math_cbrt")
    }

    @Test func testCbrtFloatOverload() throws {
        let source = "fun f(x: Float): Float = cbrt(x)"
        let link = try resolvedLink(forCall: "cbrt", withSource: source)
        #expect(link == "kk_math_cbrt_float")
    }

    // MARK: - sign family (Double / Float)

    @Test func testSignDoubleOverload() throws {
        let source = "fun f(x: Double): Double = sign(x)"
        let link = try resolvedLink(forCall: "sign", withSource: source)
        #expect(link == "kk_math_sign")
    }

    @Test func testSignFloatOverload() throws {
        let source = "fun f(x: Float): Float = sign(x)"
        let link = try resolvedLink(forCall: "sign", withSource: source)
        #expect(link == "kk_math_sign_float")
    }

    // MARK: - truncate family (Double / Float)

    @Test func testTruncateDoubleOverload() throws {
        let source = "fun f(x: Double): Double = truncate(x)"
        let link = try resolvedLink(forCall: "truncate", withSource: source)
        #expect(link == "kk_math_truncate")
    }

    @Test func testTruncateFloatOverload() throws {
        let source = "fun f(x: Float): Float = truncate(x)"
        let link = try resolvedLink(forCall: "truncate", withSource: source)
        #expect(link == "kk_math_truncate_float")
    }

    // MARK: - roundToInt / roundToLong (Double / Float)

    @Test func testRoundToIntDoubleOverload() throws {
        let source = "fun f(x: Double): Int = roundToInt(x)"
        let link = try resolvedLink(forCall: "roundToInt", withSource: source)
        #expect(link == "kk_double_roundToInt")
    }

    @Test func testRoundToIntFloatOverload() throws {
        let source = "fun f(x: Float): Int = roundToInt(x)"
        let link = try resolvedLink(forCall: "roundToInt", withSource: source)
        #expect(link == "kk_float_roundToInt")
    }

    @Test func testRoundToLongDoubleOverload() throws {
        let source = "fun f(x: Double): Long = roundToLong(x)"
        let link = try resolvedLink(forCall: "roundToLong", withSource: source)
        #expect(link == "kk_double_roundToLong")
    }

    @Test func testRoundToLongFloatOverload() throws {
        let source = "fun f(x: Float): Long = roundToLong(x)"
        let link = try resolvedLink(forCall: "roundToLong", withSource: source)
        #expect(link == "kk_float_roundToLong")
    }

    // MARK: - Unofficial rounding mode helpers

    @Test func testUnofficialRoundingModeHelpersAreNotResolvedFromKotlinMath() throws {
        let source = """
        fun f(x: Double): Double {
            val a = roundUp(x)
            val b = roundDown(x)
            val c = roundHalfEven(x)
            return a + b + c
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(ctx.diagnostics.hasError)
            let v = ctx.diagnostics.diagnostics.contains { $0.code.hasPrefix("KSWIFTK-SEMA") }
            #expect(v,
                "Expected sema diagnostics for unofficial rounding helpers"
            )
        }
    }

    // MARK: - Mixed-type overload disambiguation (Int vs Double vs Float in same scope)

    @Test func testAbsSelectsDistinctOverloadsForDifferentTypes() throws {
        let source = """
        fun f(i: Int, l: Long, d: Double, flt: Float) {
            val ai = abs(i)
            val al = abs(l)
            val ad = abs(d)
            val af = abs(flt)
        }
        """
        var results: [(String, Int)] = []
        try withTemporaryFile(contents: withKotlinMathImport(source)) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError))
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                      ctx.interner.resolve(calleeName) == "abs",
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else { continue }
                results.append((link, exprIndex))
            }
        }
        let links = results.map(\.0)
        #expect(links.contains("kk_math_abs_int"), "Int abs should resolve to kk_math_abs_int")
        #expect(links.contains("kk_math_abs_long"), "Long abs should resolve to kk_math_abs_long")
        #expect(links.contains("kk_math_abs"), "Double abs should resolve to kk_math_abs")
        #expect(links.contains("kk_math_abs_float"), "Float abs should resolve to kk_math_abs_float")
        // All 4 calls must pick distinct link names
        #expect(Set(links).count == 4, "Each abs overload should resolve to a different runtime symbol")
    }

    @Test func testSqrtSelectsDistinctOverloadsForDoubleAndFloat() throws {
        let source = """
        fun f(d: Double, flt: Float) {
            val sd = sqrt(d)
            val sf = sqrt(flt)
        }
        """
        var links: [String] = []
        try withTemporaryFile(contents: withKotlinMathImport(source)) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError))
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .call(calleeExpr, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                      ctx.interner.resolve(calleeName) == "sqrt",
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else { continue }
                links.append(link)
            }
        }
        #expect(links.contains("kk_math_sqrt"), "Double sqrt should resolve to kk_math_sqrt")
        #expect(links.contains("kk_math_sqrt_float"), "Float sqrt should resolve to kk_math_sqrt_float")
        #expect(links.count == 2)
    }

    // MARK: - FQN (fully-qualified) call resolution (PARITY-SEMA-003)

    private func resolvedLinkForFQNCall(
        lastComponent: String,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String? {
        var result: String?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!(ctx.diagnostics.hasError),
                           "Unexpected sema error for FQN call '\(lastComponent)'")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID) else { continue }
                // FQN call kotlin.math.abs(x) is a .memberCall node (not .call).
                guard case let .memberCall(_, calleeMember, _, _, _) = expr,
                      ctx.interner.resolve(calleeMember) == lastComponent
                else { continue }
                if let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee {
                    result = sema.symbols.externalLinkName(for: chosenCallee)
                }
                break
            }
        }
        return result
    }

    @Test func testFQNAbsIntOverload() throws {
        let source = "fun f(x: Int): Int = kotlin.math.abs(x)"
        let link = try resolvedLinkForFQNCall(lastComponent: "abs", withSource: source)
        #expect(link == "kk_math_abs_int")
    }

    @Test func testFQNAbsDoubleOverload() throws {
        let source = "fun f(x: Double): Double = kotlin.math.abs(x)"
        let link = try resolvedLinkForFQNCall(lastComponent: "abs", withSource: source)
        #expect(link == "kk_math_abs")
    }

    @Test func testFQNSqrtDoubleOverload() throws {
        let source = "fun f(x: Double): Double = kotlin.math.sqrt(x)"
        let link = try resolvedLinkForFQNCall(lastComponent: "sqrt", withSource: source)
        #expect(link == "kk_math_sqrt")
    }
}
#endif
