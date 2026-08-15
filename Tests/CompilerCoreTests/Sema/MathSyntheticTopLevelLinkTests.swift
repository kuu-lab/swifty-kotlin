#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct MathSyntheticTopLevelLinkTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

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

    @Test func testMathTopLevelSymbolsAreKotlinSourceBacked() throws {
        let (sema, interner) = try sharedSema()

        let expected: [String: String?] = [
            "sqrt": nil,
        ]

        for (name, expectedLink) in expected {
            #expect(
                externalLink(for: name, sema: sema, interner: interner) == expectedLink,
                "\(name) in kotlin.math should be Kotlin-source backed"
            )
        }
    }

    // KSP-637: Float overloads resolve alongside Double overloads without
    // exposing the internal native bridge as the public symbol link.
    @Test func testFloatMathOverloadsAreKotlinSourceBacked() throws {
        let (sema, interner) = try sharedSema()

        for name in [
            "sin", "cos", "tan", "asin", "acos", "atan", "atan2", "sqrt",
            "exp", "expm1", "ln", "ln1p", "log2", "log10", "log", "hypot",
        ] {
            let fq = ["kotlin", "math", name].map { interner.intern($0) }
            let allSymbols = sema.symbols.lookupAll(fqName: fq)
            let publicSymbols = allSymbols.filter { symbolID in
                sema.symbols.symbol(symbolID)?.visibility == .public
            }
            #expect(
                publicSymbols.count >= 2,
                "Expected Double and Float source overloads for \(name)"
            )
            #expect(
                publicSymbols.allSatisfy { sema.symbols.externalLinkName(for: $0) == nil },
                "Public \(name) overloads must not carry a runtime link"
            )
        }
    }

    @Test func testMathTopLevelCallsResolveWithKotlinMathImport() throws {
        let source = """
        import kotlin.math.*

        fun sample(x: Int, y: Double): Double {
            val ai = abs(-x)
            val ad = abs(y)
            return sqrt(ad * ad) + ad.pow(2.0) + ceil(ad) + floor(ad) + round(ad)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var absCalls: [ExprID] = []
            var callByName: [String: [ExprID]] = [:]

            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID) else { continue }
                guard case let .call(calleeExpr, _, _, _) = expr else { continue }
                guard case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr) else { continue }
                // Bundled stdlib sources share the arena; keep user-file calls only.
                guard ast.arena.exprRange(exprID)?.start.file == ast.sortedFiles.last?.fileID else {
                    continue
                }
                let name = ctx.interner.resolve(calleeName)
                callByName[name, default: []].append(exprID)
                if name == "abs" {
                    absCalls.append(exprID)
                }
            }

            #expect(absCalls.count == 2, "Expected int and double abs calls")

            for absCall in absCalls {
                let chosenCallee = try #require(
                    sema.bindings.callBinding(for: absCall)?.chosenCallee,
                    "Expected chosen callee for abs"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == nil,
                    "abs is Kotlin-source backed and must not carry a runtime link"
                )
            }

            let expectedOrder: [(String, String?)] = [
                ("sqrt", nil),
                ("ceil", nil),
                ("floor", nil),
                ("round", nil),
            ]
            var consumedByName: [String: Int] = [:]

            for expected in expectedOrder {
                let (name, expectedLink) = expected
                let callExpr: ExprID = {
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
    }

    @Test func testFloatingPrecisionHelpersAreSourceBackedWithKotlinMathImport() throws {
        let source = """
        import kotlin.math.*

        fun sample(x: Double, y: Float) {
            val a = x.ulp
            val b = x.nextUp()
            val c = x.nextDown()
            val d = y.ulp
            val e = y.nextUp()
            val f = y.nextDown()
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            var resolvedLinks: [String] = []
            var resolvedCount = 0
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, calleeName, _, _, _) = expr,
                      ast.arena.exprRange(exprID)?.start.file == ast.sortedFiles.last?.fileID,
                      ["ulp", "nextUp", "nextDown"].contains(ctx.interner.resolve(calleeName)),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else { continue }
                resolvedCount += 1
                if let link = sema.symbols.externalLinkName(for: chosenCallee) {
                    resolvedLinks.append(link)
                }
            }

            #expect(resolvedCount == 6, "Expected all six precision helpers to resolve")
            #expect(resolvedLinks.isEmpty, "Source-backed precision helpers must not carry runtime links")
        }
    }

    @Test func testMathExtensionPropertySymbolsUseOfficialShape() throws {
        let (sema, interner) = try sharedSema()
        let expected: [(String, TypeID, TypeID, String?)] = [
            ("absoluteValue", sema.types.doubleType, sema.types.doubleType, nil),
            ("absoluteValue", sema.types.floatType, sema.types.floatType, nil),
            ("absoluteValue", sema.types.intType, sema.types.intType, nil),
            ("absoluteValue", sema.types.longType, sema.types.longType, nil),
            ("sign", sema.types.doubleType, sema.types.doubleType, nil),
            ("sign", sema.types.floatType, sema.types.floatType, nil),
            ("sign", sema.types.intType, sema.types.intType, nil),
            ("sign", sema.types.longType, sema.types.intType, nil),
            ("ulp", sema.types.doubleType, sema.types.doubleType, nil),
            ("ulp", sema.types.floatType, sema.types.floatType, nil),
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

    @Test func testMathExtensionPropertiesResolveWithKotlinMathImport() throws {
        let source = """
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
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            #expect(!(ctx.diagnostics.hasError), "Expected math extension properties to resolve without diagnostics.")
            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let propertyNames: Set<String> = ["absoluteValue", "sign", "ulp"]
            var resolvedLinks: [String] = []
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, calleeName, _, _, _) = expr,
                      propertyNames.contains(ctx.interner.resolve(calleeName)),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
                      let link = sema.symbols.externalLinkName(for: chosenCallee)
                else {
                    continue
                }
                resolvedLinks.append(link)
            }

            #expect(resolvedLinks.isEmpty, "Math extension properties are Kotlin-source backed, got \(resolvedLinks)")
        }
    }

    @Test func testDoublePowMemberCallResolvesViaKotlinSource() throws {
        let source = """
        import kotlin.math.*

        fun sample(): Double {
            return 2.0.pow(3.0)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            #expect(!(ctx.diagnostics.hasError), "Expected Double.pow member call to resolve without diagnostics.")

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "pow"
                },
                "Expected pow member call expression"
            )

            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected chosen callee for Double.pow"
            )
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
        }
    }

    @Test func testRemainingFloatingMathMemberCallsResolveViaDefaultImport() throws {
        let source = """
        import kotlin.math.*

        fun sample(d: Double, f: Float, i: Int) {
            val ieeeD = d.IEEErem(d)
            val ieeeF = f.IEEErem(f)
            val nextD = d.nextTowards(d)
            val nextF = f.nextTowards(f)
            val powF = f.pow(f)
            val powDI = d.pow(i)
            val powFI = f.pow(i)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            #expect(!(ctx.diagnostics.hasError), "Expected remaining math member calls to resolve without diagnostics.")

            var resolvedCount = 0
            for exprIndex in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(exprIndex))
                guard let expr = ast.arena.expr(exprID),
                      case let .memberCall(_, calleeName, _, _, _) = expr,
                      ["IEEErem", "nextTowards", "pow"].contains(ctx.interner.resolve(calleeName)),
                      let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee
                else {
                    continue
                }
                resolvedCount += 1
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            }
            #expect(resolvedCount == 7, "Expected all seven migrated member calls to resolve")
        }
    }
}
#endif
