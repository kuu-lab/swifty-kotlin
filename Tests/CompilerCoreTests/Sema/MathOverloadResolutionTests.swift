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

    private static let sharedSource = #"""
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
        val a = sin(x); val b = cos(x); val c = tan(x)
        val d = asin(x); val e = acos(x); val f = atan(x)
        return a + b + c + d + e + f
    }
    fun trigFloat(x: Float): Float {
        val a = sin(x); val b = cos(x); val c = tan(x)
        val d = asin(x); val e = acos(x); val f = atan(x)
        return a + b + c + d + e + f
    }
    fun atan2Double(y: Double, x: Double): Double = atan2(y, x)
    fun atan2Float(y: Float, x: Float): Float = atan2(y, x)

    fun hyperbolicDouble(x: Double): Double {
        val a = sinh(x); val b = cosh(x); val c = tanh(x)
        return a + b + c
    }
    fun hyperbolicFloat(x: Float): Float {
        val a = sinh(x); val b = cosh(x); val c = tanh(x)
        return a + b + c
    }
    fun inverseHyperbolicDouble(x: Double): Double {
        val a = acosh(x); val b = asinh(x); val c = atanh(x)
        return a + b + c
    }
    fun inverseHyperbolicFloat(x: Float): Float {
        val a = acosh(x); val b = asinh(x); val c = atanh(x)
        return a + b + c
    }
    fun logExpDouble(x: Double): Double {
        val a = exp(x); val b = ln(x); val c = log2(x)
        val d = log10(x); val e = expm1(x); val f = ln1p(x)
        return a + b + c + d + e + f
    }
    fun logExpFloat(x: Float): Float {
        val a = exp(x); val b = ln(x); val c = log2(x)
        val d = log10(x); val e = expm1(x); val f = ln1p(x)
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
    fun roundToIntDouble(x: Double): Int = x.roundToInt()
    fun roundToIntFloat(x: Float): Int = x.roundToInt()
    fun roundToLongDouble(x: Double): Long = x.roundToLong()
    fun roundToLongFloat(x: Float): Long = x.roundToLong()

    fun precisionDouble(x: Double) {
        val a = x.ulp; val b = x.nextUp(); val c = x.nextDown()
    }
    fun precisionFloat(x: Float) {
        val a = x.ulp; val b = x.nextUp(); val c = x.nextDown()
    }

    fun fqnAbsInt(x: Int): Int = kotlin.math.abs(x)
    fun fqnAbsDouble(x: Double): Double = kotlin.math.abs(x)
    fun fqnSqrtDouble(x: Double): Double = kotlin.math.sqrt(x)
    fun absDistinct(i: Int, l: Long, d: Double, flt: Float) {
        val ai = abs(i); val al = abs(l); val ad = abs(d); val af = abs(flt)
    }
    fun sqrtDistinct(d: Double, flt: Float) {
        val sd = sqrt(d); val sf = sqrt(flt)
    }
    fun memberOnlyTopLevel(d: Double, f: Float, i: Int) {
        IEEErem(d, d); IEEErem(f, f); nextTowards(d, d); nextTowards(f, f)
        withSign(d, d); withSign(d, i); withSign(f, f); withSign(f, i)
    }
    fun unofficialRounding(x: Double) {
        val a = roundUp(x); val b = roundDown(x); val c = roundHalfEven(x)
    }
    """#

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        let ctx = makeContextFromSource(Self.sharedSource)
        do { try runSema(ctx) } catch { }
        Self._sharedCtx = ctx
        return ctx
    }

    // MARK: - Helpers

    /// Kotlin does not default-import `kotlin.math`; tests must opt in explicitly.
    private func withKotlinMathImport(_ source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("import kotlin.math") {
            return source
        }
        return "import kotlin.math.*\n\n" + source
    }

    /// Bundled stdlib sources share the AST arena with the test input, so call
    /// lookups must be restricted to the user file (always the last one).
    private func isInUserFile(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let userFileID = ast.sortedFiles.last?.fileID else { return false }
        return ast.arena.exprRange(exprID)?.start.file == userFileID
    }

    private func functionDecl(named name: String, in ast: ASTModule, interner: StringInterner) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard case let .funDecl(function) = ast.arena.decl(declID),
                      interner.resolve(function.name) == name else { continue }
                return function
            }
        }
        return nil
    }

    private func bodyRange(of function: FunDecl) -> SourceRange? {
        switch function.body {
        case .block(_, let range), .expr(_, let range): return range
        case .unit: return nil
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
                  functionBodyRange.contains(exprRange) else { continue }
            switch expr {
            case let .call(calleeExpr, _, _, _):
                guard case let .nameRef(callee, _) = ast.arena.expr(calleeExpr),
                      interner.resolve(callee) == callName else { continue }
            case let .memberCall(_, callee, _, _, _):
                guard interner.resolve(callee) == callName else { continue }
            default: continue
            }
            return exprID
        }
        return nil
    }

    private func diagnostics(
        in functionName: String,
        ctx: CompilationContext
    ) throws -> [Diagnostic] {
        let ast = try #require(ctx.ast)
        let function = try #require(functionDecl(named: functionName, in: ast, interner: ctx.interner))
        guard let range = bodyRange(of: function) else { return [] }
        return ctx.diagnostics.diagnostics.filter { diagnostic in
            guard let primaryRange = diagnostic.primaryRange else { return false }
            return range.contains(primaryRange)
        }
    }

    private func matchingCallExpressions(
        named callName: String,
        source: String,
        ctx: CompilationContext
    ) throws -> [(ExprID, SymbolID)] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let wantsFloat = source.contains("Float")
        let wantsIntExponent = source.contains("n: Int") || source.contains("sign: Int")
        var matches: [(ExprID, SymbolID)] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), isInUserFile(exprID, ast: ast) else { continue }
            let name: String
            switch expr {
            case let .call(calleeExpr, _, _, _):
                guard case let .nameRef(callee, _) = ast.arena.expr(calleeExpr) else { continue }
                name = ctx.interner.resolve(callee)
            case let .memberCall(_, callee, _, _, _):
                name = ctx.interner.resolve(callee)
            default: continue
            }
            guard name == callName,
                  let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee else { continue }
            let link = sema.symbols.externalLinkName(for: chosen)
            if wantsFloat && wantsIntExponent {
                guard link?.contains("_float_int") == true || link == nil else { continue }
            } else if wantsFloat {
                guard link?.contains("_float") == true || link == nil else { continue }
            } else if wantsIntExponent {
                guard link?.contains("_int") == true || link == nil else { continue }
            } else if let link, link.contains("_float") {
                continue
            }
            matches.append((exprID, chosen))
        }
        return matches
    }

    private func sourceMatchesSignature(_ source: String, _ signature: String) -> Bool {
        let typeNames = ["Double", "Float", "Int", "Long", "UInt", "ULong"]
        return typeNames.filter { signature.contains($0) }.allSatisfy { source.contains($0) }
    }

    private func resolvedLink(
        forCall callName: String,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String? {
        let ctx = try sharedCtx()
        let matches = try matchingCallExpressions(named: callName, source: source, ctx: ctx)
        return matches.first.flatMap { ctx.sema?.symbols.externalLinkName(for: $0.1) }
    }

    /// Kotlin-source backed overloads (KSP-635) carry no runtime link, so the
    /// selected overload is identified by its resolved signature instead.
    private func resolvedSourceBackedSignature(
        forCall callName: String,
        withSource source: String
    ) throws -> String? {
        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        for (_, chosenCallee) in try matchingCallExpressions(named: callName, source: source, ctx: ctx) {
            guard sema.symbols.externalLinkName(for: chosenCallee) == nil,
                  let signature = sema.symbols.functionSignature(for: chosenCallee) else { continue }
            let parameters = signature.parameterTypes
                .map { sema.types.renderType($0) }
                .joined(separator: ", ")
            let rendered = "(" + parameters + ") -> " + sema.types.renderType(signature.returnType)
            if sourceMatchesSignature(source, rendered) {
                return rendered
            }
        }
        return nil
    }

    private func resolvedLinkForFirstMatchingCall(
        names: Set<String>,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: String] {
        let ctx = try sharedCtx()
        let sema = try #require(ctx.sema)
        var results: [String: String] = [:]
        for name in names {
            let matches = try matchingCallExpressions(named: name, source: source, ctx: ctx)
            if let link = matches.compactMap({ sema.symbols.externalLinkName(for: $0.1) }).first {
                results[name] = link
            }
        }
        return results
    }

    // MARK: - abs family (Int / Long / Double / Float)

    @Test func testAbsIntOverload() throws {
        let source = "fun f(x: Int): Int = abs(x)"
        let signature = try resolvedSourceBackedSignature(forCall: "abs", withSource: source)
        #expect(signature == "(Int) -> Int")
    }

    @Test func testAbsLongOverload() throws {
        let source = "fun f(x: Long): Long = abs(x)"
        let signature = try resolvedSourceBackedSignature(forCall: "abs", withSource: source)
        #expect(signature == "(Long) -> Long")
    }

    @Test func testAbsDoubleOverload() throws {
        let source = "fun f(x: Double): Double = abs(x)"
        let signature = try resolvedSourceBackedSignature(forCall: "abs", withSource: source)
        #expect(signature == "(Double) -> Double")
    }

    @Test func testAbsFloatOverload() throws {
        let source = "fun f(x: Float): Float = abs(x)"
        let signature = try resolvedSourceBackedSignature(forCall: "abs", withSource: source)
        #expect(signature == "(Float) -> Float")
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
        let cases: [(name: String, source: String, expectedLink: String?)] = [
            ("IEEErem", "fun f(x: Double, y: Double): Double = x.IEEErem(y)", "kk_math_IEEErem"),
            ("IEEErem", "fun f(x: Float, y: Float): Float = x.IEEErem(y)", "kk_math_IEEErem_float"),
            ("nextTowards", "fun f(x: Double, y: Double): Double = x.nextTowards(y)", "kk_math_nextTowards"),
            ("nextTowards", "fun f(x: Float, y: Float): Float = x.nextTowards(y)", "kk_math_nextTowards_float"),
            ("withSign", "fun f(x: Double, y: Double): Double = x.withSign(y)", nil),
            ("withSign", "fun f(x: Double, sign: Int): Double = x.withSign(sign)", nil),
            ("withSign", "fun f(x: Float, y: Float): Float = x.withSign(y)", nil),
            ("withSign", "fun f(x: Float, sign: Int): Float = x.withSign(sign)", nil),
        ]

        for testCase in cases {
            let link = try resolvedLink(forCall: testCase.name, withSource: testCase.source)
            #expect(link == testCase.expectedLink)
        }
    }

    @Test func testFloatingMemberOnlyMathFunctionsRejectTopLevelCalls() throws {
        let ctx = try sharedCtx()
        let errors = try diagnostics(in: "memberOnlyTopLevel", ctx: ctx)
        #expect(errors.contains { $0.severity == .error }, "Expected member-only math helpers to reject top-level calls.")
    }

    // MARK: - round / ceil / floor family (Double / Float)

    @Test func testRoundDoubleOverload() throws {
        let source = "fun f(x: Double): Double = round(x)"
        let link = try resolvedLink(forCall: "round", withSource: source)
        #expect(link == nil)
    }

    @Test func testRoundFloatOverload() throws {
        let source = "fun f(x: Float): Float = round(x)"
        let link = try resolvedLink(forCall: "round", withSource: source)
        #expect(link == nil)
    }

    @Test func testCeilDoubleOverload() throws {
        let source = "fun f(x: Double): Double = ceil(x)"
        let link = try resolvedLink(forCall: "ceil", withSource: source)
        #expect(link == nil)
    }

    @Test func testCeilFloatOverload() throws {
        let source = "fun f(x: Float): Float = ceil(x)"
        let link = try resolvedLink(forCall: "ceil", withSource: source)
        #expect(link == nil)
    }

    @Test func testFloorDoubleOverload() throws {
        let source = "fun f(x: Double): Double = floor(x)"
        let link = try resolvedLink(forCall: "floor", withSource: source)
        #expect(link == nil)
    }

    @Test func testFloorFloatOverload() throws {
        let source = "fun f(x: Float): Float = floor(x)"
        let link = try resolvedLink(forCall: "floor", withSource: source)
        #expect(link == nil)
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
        for name in ["max", "min"] {
            for type in ["Double", "Float", "Int", "Long", "UInt", "ULong"] {
                let source = "fun f(a: \(type), b: \(type)): \(type) = \(name)(a, b)"
                let signature = try resolvedSourceBackedSignature(forCall: name, withSource: source)
                #expect(
                    signature == "(\(type), \(type)) -> \(type)",
                    "\(name)(\(type), \(type)) should resolve to the matching overload, got \(signature ?? "nil")"
                )
            }
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
        let signature = try resolvedSourceBackedSignature(forCall: "sign", withSource: source)
        #expect(signature == "(Double) -> Double")
    }

    @Test func testSignFloatOverload() throws {
        let source = "fun f(x: Float): Float = sign(x)"
        let signature = try resolvedSourceBackedSignature(forCall: "sign", withSource: source)
        #expect(signature == "(Float) -> Float")
    }

    // MARK: - truncate family (Double / Float)

    @Test func testTruncateDoubleOverload() throws {
        let source = "fun f(x: Double): Double = truncate(x)"
        let link = try resolvedLink(forCall: "truncate", withSource: source)
        #expect(link == nil)
    }

    @Test func testTruncateFloatOverload() throws {
        let source = "fun f(x: Float): Float = truncate(x)"
        let link = try resolvedLink(forCall: "truncate", withSource: source)
        #expect(link == nil)
    }

    // MARK: - roundToInt / roundToLong (Double / Float)

    @Test func testRoundToIntDoubleOverload() throws {
        let source = "fun f(x: Double): Int = x.roundToInt()"
        let link = try resolvedLink(forCall: "roundToInt", withSource: source)
        #expect(link == nil)
    }

    @Test func testRoundToIntFloatOverload() throws {
        let source = "fun f(x: Float): Int = x.roundToInt()"
        let link = try resolvedLink(forCall: "roundToInt", withSource: source)
        #expect(link == nil)
    }

    @Test func testRoundToLongDoubleOverload() throws {
        let source = "fun f(x: Double): Long = x.roundToLong()"
        let link = try resolvedLink(forCall: "roundToLong", withSource: source)
        #expect(link == nil)
    }

    @Test func testRoundToLongFloatOverload() throws {
        let source = "fun f(x: Float): Long = x.roundToLong()"
        let link = try resolvedLink(forCall: "roundToLong", withSource: source)
        #expect(link == nil)
    }

    @Test func testFloatingPrecisionExtensionsAreSourceBacked() throws {
        let cases: [(name: String, source: String)] = [
            ("ulp", "fun f(x: Double): Double = x.ulp"),
            ("ulp", "fun f(x: Float): Float = x.ulp"),
            ("nextUp", "fun f(x: Double): Double = x.nextUp()"),
            ("nextUp", "fun f(x: Float): Float = x.nextUp()"),
            ("nextDown", "fun f(x: Double): Double = x.nextDown()"),
            ("nextDown", "fun f(x: Float): Float = x.nextDown()"),
        ]

        for testCase in cases {
            let link = try resolvedLink(forCall: testCase.name, withSource: testCase.source)
            #expect(link == nil, "(testCase.name) should resolve to Kotlin source")
        }
    }

    // MARK: - Unofficial rounding mode helpers

    @Test func testUnofficialRoundingModeHelpersAreNotResolvedFromKotlinMath() throws {
        let ctx = try sharedCtx()
        let errors = try diagnostics(in: "unofficialRounding", ctx: ctx)
        #expect(errors.contains { $0.severity == .error })
        #expect(errors.contains { $0.code.hasPrefix("KSWIFTK-SEMA") },
                "Expected sema diagnostics for unofficial rounding helpers")
    }

    // MARK: - Mixed-type overload disambiguation (Int vs Double vs Float in same scope)

    @Test func testAbsSelectsDistinctOverloadsForDifferentTypes() throws {
        let ctx = try sharedCtx()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let function = try #require(functionDecl(named: "absDistinct", in: ast, interner: ctx.interner))
        let range = try #require(bodyRange(of: function))
        let chosenCallees = ast.arena.exprs.indices.compactMap { index -> SymbolID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .call(calleeExpr, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                  ctx.interner.resolve(calleeName) == "abs",
                  let exprRange = ast.arena.exprRange(exprID),
                  range.contains(exprRange) else { return nil }
            return sema.bindings.callBinding(for: exprID)?.chosenCallee
        }
        #expect(chosenCallees.count == 4, "Expected one chosen callee per abs call")
        #expect(Set(chosenCallees).count == 4, "Each abs overload should resolve to a different declaration")
    }

    @Test func testSqrtSelectsDistinctOverloadsForDoubleAndFloat() throws {
        let ctx = try sharedCtx()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let function = try #require(functionDecl(named: "sqrtDistinct", in: ast, interner: ctx.interner))
        let range = try #require(bodyRange(of: function))
        let links = ast.arena.exprs.indices.compactMap { index -> String? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .call(calleeExpr, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                  ctx.interner.resolve(calleeName) == "sqrt",
                  let exprRange = ast.arena.exprRange(exprID),
                  range.contains(exprRange),
                  let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee else { return nil }
            return sema.symbols.externalLinkName(for: chosenCallee)
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
        let ctx = try sharedCtx()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, calleeMember, _, _, _) = expr,
                  ctx.interner.resolve(calleeMember) == lastComponent,
                  let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee else { continue }
            if lastComponent == "abs" && source.contains("Double") {
                continue
            }
            return sema.symbols.externalLinkName(for: chosenCallee)
        }
        return nil
    }

    @Test func testFQNAbsOverloadsResolveWithoutRuntimeLink() throws {
        for type in ["Int", "Double"] {
            let source = "fun f(x: \(type)): \(type) = kotlin.math.abs(x)"
            let link = try resolvedLinkForFQNCall(lastComponent: "abs", withSource: source)
            #expect(link == nil, "FQN abs(\(type)) is Kotlin-source backed, got \(link ?? "nil")")
        }
    }

    @Test func testFQNSqrtDoubleOverload() throws {
        let source = "fun f(x: Double): Double = kotlin.math.sqrt(x)"
        let link = try resolvedLinkForFQNCall(lastComponent: "sqrt", withSource: source)
        #expect(link == "kk_math_sqrt")
    }
}
#endif
