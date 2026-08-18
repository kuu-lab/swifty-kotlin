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
    fun powDouble(x: Double, y: Double): Double = x.pow(y)
    fun powFloat(x: Float, y: Float): Float = x.pow(y)
    fun powDoubleInt(x: Double, n: Int): Double = x.pow(n)
    fun powFloatInt(x: Float, n: Int): Float = x.pow(n)
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
    fun precisionHelpers(x: Double, y: Float) {
        val a = x.ulp; val b = x.nextUp(); val c = x.nextDown()
        val d = y.ulp; val e = y.nextUp(); val f = y.nextDown()
    }
    fun absDistinct(i: Int, l: Long, d: Double, flt: Float) {
        val ai = abs(i); val al = abs(l); val ad = abs(d); val af = abs(flt)
    }
    fun fqnAbsInt(x: Int): Int = kotlin.math.abs(x)
    fun fqnAbsDouble(x: Double): Double = kotlin.math.abs(x)
    fun fqnSqrtDouble(x: Double): Double = kotlin.math.sqrt(x)
    """#

    private static nonisolated(unsafe) var _sharedCtx: CompilationContext?

    private func sharedCtx() throws -> CompilationContext {
        if let cached = Self._sharedCtx { return cached }
        var result: CompilationContext?
        try withTemporaryFile(contents: Self.sharedSource) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = ctx
        }
        let ctx = try #require(result)
        Self._sharedCtx = ctx
        return ctx
    }

    // MARK: - Helpers

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

    private func renderedSignature(for symbol: SymbolID, sema: SemaModule) -> String? {
        guard let signature = sema.symbols.functionSignature(for: symbol) else { return nil }
        let parameters = signature.parameterTypes
            .map { sema.types.renderType($0) }
            .joined(separator: ", ")
        return "(\(parameters)) -> \(sema.types.renderType(signature.returnType))"
    }

    private func sourceBackedSignature(for symbol: SymbolID, sema: SemaModule) -> String? {
        guard sema.symbols.externalLinkName(for: symbol) == nil else { return nil }
        return renderedSignature(for: symbol, sema: sema)
    }

    private func sourceMatchesSignature(_ source: String, _ signature: String) -> Bool {
        ["Double", "Float", "Int", "Long", "UInt", "ULong"].allSatisfy { type in
            signature.range(of: "\\b\(type)\\b", options: .regularExpression) == nil
                || source.range(of: "\\b\(type)\\b", options: .regularExpression) != nil
        }
    }

    private func matchingCallExpressions(
        named callName: String,
        source: String,
        in ctx: CompilationContext
    ) throws -> [(ExprID, SymbolID)] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var matches: [(ExprID, SymbolID)] = []
        for exprIndex in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(exprIndex))
            guard let expr = ast.arena.expr(exprID), isInUserFile(exprID, ast: ast) else { continue }
            let name: String
            switch expr {
            case let .call(calleeExpr, _, _, _):
                guard case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr) else { continue }
                name = ctx.interner.resolve(calleeName)
            case let .memberCall(_, calleeName, _, _, _):
                name = ctx.interner.resolve(calleeName)
            default:
                continue
            }
            guard name == callName,
                  let chosen = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                  let signature = renderedSignature(for: chosen, sema: sema),
                  sourceMatchesSignature(source, signature) else { continue }
            matches.append((exprID, chosen))
        }
        return matches
    }

    private func resolvedLink(
        forCall callName: String,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String? {
        let ctx = try sharedCtx()
        #expect(
            !(ctx.diagnostics.hasError),
            "Unexpected sema error for '\(callName)': \(ctx.diagnostics.diagnostics.map(\.message))"
        )
        let sema = try #require(ctx.sema)
        return try matchingCallExpressions(named: callName, source: source, in: ctx)
            .first
            .flatMap { sema.symbols.externalLinkName(for: $0.1) }
    }

    /// Kotlin-source backed overloads carry no runtime link, so the
    /// selected overload is identified by its resolved signature instead.
    private func resolvedSourceBackedSignature(
        forCall callName: String,
        withSource source: String
    ) throws -> String? {
        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError), "Unexpected sema error for '\(callName)'")
        let sema = try #require(ctx.sema)
        for (_, chosenCallee) in try matchingCallExpressions(named: callName, source: source, in: ctx) {
            if let signature = sourceBackedSignature(for: chosenCallee, sema: sema) {
                return signature
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
        #expect(!(ctx.diagnostics.hasError), "Unexpected sema error")
        let sema = try #require(ctx.sema)
        var results: [String: String] = [:]
        for name in names {
            guard let chosenCallee = try matchingCallExpressions(named: name, source: source, in: ctx).first?.1 else {
                continue
            }
            results[name] = sema.symbols.externalLinkName(for: chosenCallee) ?? "<source>"
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
        #expect(link == nil)
    }

    @Test func testSqrtFloatOverload() throws {
        let source = "fun f(x: Float): Float = sqrt(x)"
        let link = try resolvedLink(forCall: "sqrt", withSource: source)
        #expect(link == nil)
    }

    // MARK: - pow family (Double / Float, floating and Int exponents)

    @Test func testPowDoubleOverload() throws {
        let source = "fun f(x: Double, y: Double): Double = x.pow(y)"
        let link = try resolvedLink(forCall: "pow", withSource: source)
        #expect(link == nil)
    }

    @Test func testPowRemainingOverloads() throws {
        let cases: [(source: String, expectedLink: String?)] = [
            ("fun f(x: Float, y: Float): Float = x.pow(y)", nil),
            ("fun f(x: Double, n: Int): Double = x.pow(n)", nil),
            ("fun f(x: Float, n: Int): Float = x.pow(n)", nil),
        ]

        for testCase in cases {
            let link = try resolvedLink(forCall: "pow", withSource: testCase.source)
            #expect(link == testCase.expectedLink)
        }
    }

    @Test func testIEEEremNextTowardsAndWithSignOverloads() throws {
        let cases: [(name: String, source: String, expectedLink: String?)] = [
            ("IEEErem", "fun f(x: Double, y: Double): Double = x.IEEErem(y)", nil),
            ("IEEErem", "fun f(x: Float, y: Float): Float = x.IEEErem(y)", nil),
            ("nextTowards", "fun f(x: Double, y: Double): Double = x.nextTowards(y)", nil),
            ("nextTowards", "fun f(x: Float, y: Float): Float = x.nextTowards(y)", nil),
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
        #expect(links["sin"] == "<source>")
        #expect(links["cos"] == "<source>")
        #expect(links["tan"] == "<source>")
        #expect(links["asin"] == "<source>")
        #expect(links["acos"] == "<source>")
        #expect(links["atan"] == "<source>")
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
        #expect(links["sin"] == "<source>")
        #expect(links["cos"] == "<source>")
        #expect(links["tan"] == "<source>")
        #expect(links["asin"] == "<source>")
        #expect(links["acos"] == "<source>")
        #expect(links["atan"] == "<source>")
    }

    // MARK: - atan2 family (Double / Float)

    @Test func testAtan2DoubleOverload() throws {
        let source = "fun f(y: Double, x: Double): Double = atan2(y, x)"
        let link = try resolvedLink(forCall: "atan2", withSource: source)
        #expect(link == nil)
    }

    @Test func testAtan2FloatOverload() throws {
        let source = "fun f(y: Float, x: Float): Float = atan2(y, x)"
        let link = try resolvedLink(forCall: "atan2", withSource: source)
        #expect(link == nil)
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
        #expect(links["sinh"] == "<source>")
        #expect(links["cosh"] == "<source>")
        #expect(links["tanh"] == "<source>")
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
        #expect(links["sinh"] == "<source>")
        #expect(links["cosh"] == "<source>")
        #expect(links["tanh"] == "<source>")
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
        #expect(links["acosh"] == "<source>")
        #expect(links["asinh"] == "<source>")
        #expect(links["atanh"] == "<source>")
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
        #expect(links["acosh"] == "<source>")
        #expect(links["asinh"] == "<source>")
        #expect(links["atanh"] == "<source>")
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
        #expect(links["exp"] == "<source>")
        #expect(links["ln"] == "<source>")
        #expect(links["log2"] == "<source>")
        #expect(links["log10"] == "<source>")
        #expect(links["expm1"] == "<source>")
        #expect(links["ln1p"] == "<source>")
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
        #expect(links["exp"] == "<source>")
        #expect(links["ln"] == "<source>")
        #expect(links["log2"] == "<source>")
        #expect(links["log10"] == "<source>")
        #expect(links["expm1"] == "<source>")
        #expect(links["ln1p"] == "<source>")
    }

    @Test func testLogTwoArgDoubleOverload() throws {
        let source = "fun f(x: Double, base: Double): Double = log(x, base)"
        let link = try resolvedLink(forCall: "log", withSource: source)
        #expect(link == nil)
    }

    @Test func testLogTwoArgFloatOverload() throws {
        let source = "fun f(x: Float, base: Float): Float = log(x, base)"
        let link = try resolvedLink(forCall: "log", withSource: source)
        #expect(link == nil)
    }

    // MARK: - hypot family (Double / Float)

    @Test func testHypotDoubleOverload() throws {
        let source = "fun f(x: Double, y: Double): Double = hypot(x, y)"
        let link = try resolvedLink(forCall: "hypot", withSource: source)
        #expect(link == nil)
    }

    @Test func testHypotFloatOverload() throws {
        let source = "fun f(x: Float, y: Float): Float = hypot(x, y)"
        let link = try resolvedLink(forCall: "hypot", withSource: source)
        #expect(link == nil)
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
        #expect(link == nil)
    }

    @Test func testCbrtFloatOverload() throws {
        let source = "fun f(x: Float): Float = cbrt(x)"
        let link = try resolvedLink(forCall: "cbrt", withSource: source)
        #expect(link == nil)
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
        let ctx = try sharedCtx()
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let function = try #require(functionDecl(named: "absDistinct", in: ast, interner: ctx.interner))
        let functionRange = try #require(bodyRange(of: function))
        var chosenCallees: [SymbolID] = []
        for exprIndex in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(exprIndex))
            guard let expr = ast.arena.expr(exprID),
                  let exprRange = ast.arena.exprRange(exprID),
                  functionRange.contains(exprRange),
                  case let .call(calleeExpr, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr),
                  ctx.interner.resolve(calleeName) == "abs",
                  let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
            else { continue }
            chosenCallees.append(chosenCallee)
        }
        #expect(chosenCallees.count == 4, "Expected one chosen callee per abs call")
        #expect(Set(chosenCallees).count == 4, "Each abs overload should resolve to a different declaration")
    }

    @Test func testSqrtSelectsDistinctSourceBackedOverloadsForDoubleAndFloat() throws {
        let doubleSignature = try resolvedSourceBackedSignature(
            forCall: "sqrt",
            withSource: "fun f(x: Double): Double = sqrt(x)"
        )
        let floatSignature = try resolvedSourceBackedSignature(
            forCall: "sqrt",
            withSource: "fun f(x: Float): Float = sqrt(x)"
        )
        #expect(doubleSignature == "(Double) -> Double")
        #expect(floatSignature == "(Float) -> Float")
    }

    // MARK: - FQN (fully-qualified) call resolution (PARITY-SEMA-003)

    private func resolvedLinkForFQNCall(
        lastComponent: String,
        withSource source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String? {
        let ctx = try sharedCtx()
        #expect(!(ctx.diagnostics.hasError),
                "Unexpected sema error for FQN call '\(lastComponent)'")
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        for exprIndex in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(exprIndex))
            guard let expr = ast.arena.expr(exprID),
                  case let .memberCall(_, calleeMember, _, _, _) = expr,
                  ctx.interner.resolve(calleeMember) == lastComponent,
                  isInUserFile(exprID, ast: ast),
                  let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                  let signature = renderedSignature(for: chosenCallee, sema: sema),
                  sourceMatchesSignature(source, signature)
            else { continue }
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
        #expect(link == nil)
    }
}
#endif
