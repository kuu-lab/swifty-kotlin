#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ComparisonSyntheticTopLevelTests {
    private func lastExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices.reversed() {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    @Test
    func testMaxOfMinOfAndCompareByOverloadsResolve() throws {
        let sources: [String] = [
            """
                    fun sample0(): Int {
                        val hi = maxOf(3, 7)
                        val lo = minOf(3, 7)
                        return hi - lo
                    }
            """,
            """
                    fun sample1() {
                        val ascending = compareBy<Int> { it % 10 }
                        val descending = compareByDescending<Int> { it % 10 }
                        println(listOf(231, 114, 123).sortedWith(ascending))
                        println(listOf(231, 114, 123).sortedWith(descending))
                    }
            """,
            """
                    fun sample2() {
                        val cmp = compareByDescending<String, Int>(compareBy<Int> { it }) { it.length }
                        println(listOf("pear", "fig", "apple").sortedWith(cmp))
                    }
            """,
            """
                    fun sample3() {
                        val cmp = compareBy<String, Int>(compareBy<Int> { it }) { it.length }
                        println(listOf("pear", "fig", "apple").sortedWith(cmp))
                    }
            """,
            """
                    fun sample4(): Int {
                        val hi = maxOf(1, 5, 3)
                        val lo = minOf(1, 5, 3)
                        return hi - lo
                    }
            """,
            """
                    fun sample5(): Long {
                        val hi = maxOf(1L, 5L, 3L)
                        val lo = minOf(1L, 5L, 3L)
                        return hi - lo
                    }
            """,
            """
                    fun sample6(): Double {
                        val hi = maxOf(1.0, 5.0, 3.0)
                        val lo = minOf(1.0, 5.0, 3.0)
                        return hi - lo
                    }
            """,
            """
                    fun sample7() {
                        val generic2 = maxOf("b", "a")
                        val genericVararg = maxOf("d", "b", "a", "c")
                        val comparator3 = maxOf(1, 2, reverseOrder<Int>())
                        val comparatorVararg = maxOf(1, 4, 2, 3, reverseOrder<Int>())
                        val unsigned2 = maxOf(1u, 4000000000u)
                        val unsigned3 = maxOf(1u, 3u, 4000000000u)
                        println(generic2)
                        println(genericVararg)
                        println(comparator3)
                        println(comparatorVararg)
                        println(unsigned2)
                        println(unsigned3)
                    }
            """,
            """
                    fun sample8() {
                        val unsignedMin2 = minOf(1u, 4000000000u)
                        val unsignedMin3 = minOf(1u, 3u, 4000000000u)
                        println(unsignedMin2)
                        println(unsignedMin3)
                    }
            """,
            """
                    fun sample9(a: Byte, b: Byte, c: Byte): Byte = maxOf(a, b, c)
            """,
            """
                    fun sample10(a: Short, b: Short, c: Short): Short = maxOf(a, b, c)
            """,
            """
                    fun sample11(a: Int, b: Int): Int = minOf(a, b)
            """,
            """
                    fun sample12(): Int = minOf(5, 2, 8, 1)
            """,
            """
                    fun sample13(a: Byte, b: Byte): Byte = minOf(a, b)
            """,
            """
                    fun sample14(a: Byte, b: Byte, c: Byte, d: Byte): Byte = minOf(a, b, c, d)
            """,
            """
                    fun sample15(a: Byte, b: Byte, c: Byte, d: Byte): Byte = maxOf(a, b, c, d)
            """,
            """
                    fun sample16(a: Float, b: Float): Float = maxOf(a, b)
            """,
            """
                    fun sample17(a: Float, b: Float, c: Float): Float = maxOf(a, b, c)
            """,
            """
                    fun sample18(a: Float, b: Float): Float = minOf(a, b)
            """,
            """
                    fun sample19(a: Double, b: Double): Double = maxOf(a, b)
            """,
            """
                    fun sample20(a: Double, b: Double): Double = minOf(a, b)
            """,
            """
                    fun sample21(a: Double, b: Double, c: Double): Double = maxOf(a, b, c)
            """,
            """
                    fun sample22(a: Double, b: Double, c: Double): Double = minOf(a, b, c)
            """,
            """
                    fun sample23(a: Float, b: Float, c: Float): Float = minOf(a, b, c)
            """,
            """
                    fun sample24() {
                        val generic2 = minOf("b", "a")
                        val genericVararg = minOf("d", "b", "a", "c")
                        val comparator3 = minOf(1, 2, reverseOrder<Int>())
                        val comparatorVararg = minOf(1, 4, 2, 3, reverseOrder<Int>())
                        val unsigned2 = minOf(1u, 4000000000u)
                        val unsigned3 = minOf(1u, 3u, 4000000000u)
                        println(generic2)
                        println(genericVararg)
                        println(comparator3)
                        println(comparatorVararg)
                        println(unsigned2)
                        println(unsigned3)
                    }
            """,
            """
                    fun sample25(a: Long, b: Long): Long = maxOf(a, b)
            """,
            """
                    fun sample26(a: Long, b: Long): Long = minOf(a, b)
            """,
            """
                    fun sample27(a: ULong, b: ULong): ULong = minOf(a, b)
            """,
            """
                    fun sample28(a: ULong, b: ULong, c: ULong): ULong = minOf(a, b, c)
            """,
            """
                    fun sample29(): ULong = minOf(5uL, 2uL, 8uL, 1uL)
            """,
            """
                    fun sample30(): Float = minOf(5.0f, 2.0f, 8.0f, 1.0f)
            """,
            """
                    fun sample31(): Long = maxOf(5L, 2L, 8L, 1L)
            """,
            """
                    fun sample32(): Long = minOf(5L, 2L, 8L, 1L)
            """,
            """
                    fun sample33(a: UShort, b: UShort): UShort = minOf(a, b)
            """,
            """
                    fun sample34(a: UShort, b: UShort, c: UShort): UShort = minOf(a, b, c)
            """,
            """
                    fun sample35(a: UShort, b: UShort, c: UShort, d: UShort): UShort = minOf(a, b, c, d)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            // === testMaxOfAndMinOfResolveToSyntheticComparisonFunctions ===
            do {
                for name in ["maxOf", "minOf"] {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[0], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, _, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == name
                        })
                    #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                    let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                    #expect(kind == (name == "maxOf" ? .maxOfInt : .minOfInt))
                    let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let symbol = try #require(sema.symbols.symbol(chosen))
                    #expect(symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("comparisons"),
                        interner.intern(name),
                    ])
                }
            }

            // === testCompareByAndCompareByDescendingResolveToBundledStdlibFunctions ===
            do {
                for name in ["compareBy", "compareByDescending"] {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[1], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, _, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == name
                        })
                    let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let symbol = try #require(sema.symbols.symbol(chosenCallee))
                    #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "comparisons", name], "Expected \(name) to resolve to kotlin.comparisons.\(name)")
                    #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil, "Expected \(name) to be source-backed without a runtime comparator link")
                }
            }

            // === testCompareByDescendingComparatorSelectorResolvesToBundledStdlibFunction ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[2], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, args, _, _) = expr,
                              args.count == 2,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == "compareByDescending"
                    })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "comparisons", "compareByDescending"])
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            }

            // === testCompareByComparatorSelectorResolvesToBundledStdlibFunction ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[3], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, args, _, _) = expr,
                              args.count == 2,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == "compareBy"
                    })
                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "comparisons", "compareBy"])
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == nil)
            }

            // === testThreeArgMaxOfMinOfResolveToSyntheticComparisonFunctions ===
            do {
                for name in ["maxOf", "minOf"] {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[4], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, args, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == name && args.count == 3
                        })
                    #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                    let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                    #expect(kind == (name == "maxOf" ? .maxOfInt3 : .minOfInt3))
                    let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let symbol = try #require(sema.symbols.symbol(chosen))
                    #expect(symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("comparisons"),
                        interner.intern(name),
                    ])
                    // Verify 3-param signature
                    let sig = try #require(sema.symbols.functionSignature(for: chosen))
                    #expect(sig.parameterTypes.count == 3)
                }
            }

            // === testThreeArgMaxOfMinOfLongOverload ===
            do {
                for name in ["maxOf", "minOf"] {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[5], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, args, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == name && args.count == 3
                        })
                    #expect(sema.bindings.exprTypes[callExpr] == sema.types.longType)
                    let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                    #expect(kind == (name == "maxOf" ? .maxOfLong3 : .minOfLong3))
                }
            }

            // === testThreeArgMaxOfMinOfDoubleOverload ===
            do {
                for name in ["maxOf", "minOf"] {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[6], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, args, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == name && args.count == 3
                        })
                    #expect(sema.bindings.exprTypes[callExpr] == sema.types.doubleType)
                    let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                    #expect(kind == (name == "maxOf" ? .maxOfDouble3 : .minOfDouble3))
                }
            }

            // === testRemainingMaxOfOverloadsResolveToSyntheticComparisonFunctions ===
            do {
                let expectedCases: [(argCount: Int, returnType: TypeID)] = [
                    (2, sema.types.stringType),
                    (4, sema.types.stringType),
                    (3, sema.types.intType),
                    (5, sema.types.intType),
                    (2, sema.types.uintType),
                    (3, sema.types.uintType),
                ]
                for expected in expectedCases {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[7], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, args, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == "maxOf"
                                && args.count == expected.argCount
                                && sema.bindings.exprTypes[exprID] == expected.returnType
                        })
                    #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                    let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let symbol = try #require(sema.symbols.symbol(chosen))
                    #expect(symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("comparisons"),
                        interner.intern("maxOf"),
                    ])
                    #expect(sema.bindings.exprTypes[callExpr] == expected.returnType)
                }
            }

            // === testRemainingMinOfUnsignedOverloadsResolveToSyntheticComparisonFunctions ===
            do {
                let expectedCases: [(argCount: Int, returnType: TypeID)] = [
                    (2, sema.types.uintType),
                    (3, sema.types.uintType),
                ]
                for expected in expectedCases {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[8], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, args, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == "minOf"
                                && args.count == expected.argCount
                                && sema.bindings.exprTypes[exprID] == expected.returnType
                        })
                    #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                    let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let symbol = try #require(sema.symbols.symbol(chosen))
                    #expect(symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("comparisons"),
                        interner.intern("minOf"),
                    ])
                    #expect(sema.bindings.exprTypes[callExpr] == expected.returnType)
                }
            }

            // === testThreeArgMaxOfByteResolvesToInt3Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[9], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 3
                    })
                // Byte maps to Int internally, so the result type is Int
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                // Resolves via the Int3 special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .maxOfInt3)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType, sema.types.intType])
            }

            // === testThreeArgMaxOfShortResolvesToInt3Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[10], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 3
                    })
                // Short maps to Int internally, so the result type is Int
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                // Resolves via the Int3 special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .maxOfInt3)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType, sema.types.intType])
            }

            // === testTwoArgMinOfIntResolvesToInt2Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[11], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 2
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                // Resolves via the Int 2-arg special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .minOfInt)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType])
            }

            // === testVarargMinOfIntResolvesToVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[12], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 4
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType])
                #expect(sig.returnType == sema.types.intType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

            // === testTwoArgMinOfByteResolvesToInt2Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[13], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 2
                    })
                // Byte maps to Int internally, so the result type is Int
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                // Resolves via the Int 2-arg special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .minOfInt)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType])
            }

            // === testVarargMinOfByteResolvesToIntVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[14], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 4
                    })
                // Byte maps to Int internally, so the result type is Int
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType])
                #expect(sig.returnType == sema.types.intType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

            // === testVarargMaxOfByteResolvesToIntVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[15], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 4
                    })
                // Byte maps to Int internally, so the result type is Int
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.intType)
                // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.intType, sema.types.intType])
                #expect(sig.returnType == sema.types.intType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

            // === testTwoArgMaxOfFloatResolvesToFloat2Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[16], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 2
                    })
                // Float is preserved end-to-end (no widening to Double)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.floatType)
                // Resolves via the Float 2-arg special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .maxOfFloat)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.floatType, sema.types.floatType])
            }

            // === testThreeArgMaxOfFloatResolvesToFloat3Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[17], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 3
                    })
                // Float is preserved end-to-end (no widening to Double)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.floatType)
                // Resolves via the Float3 special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .maxOfFloat3)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.floatType, sema.types.floatType, sema.types.floatType])
            }

            // === testTwoArgMinOfFloatResolvesToFloat2Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[18], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 2
                    })
                // Float is preserved end-to-end (no widening to Double)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.floatType)
                // Resolves via the Float 2-arg special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .minOfFloat)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.floatType, sema.types.floatType])
            }

            // === testTwoArgMaxOfDoubleResolvesToDoubleOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[19], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 2
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.doubleType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .maxOfDouble)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.doubleType, sema.types.doubleType])
            }

            // === testTwoArgMinOfDoubleResolvesToDoubleOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[20], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 2
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.doubleType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .minOfDouble)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.doubleType, sema.types.doubleType])
            }

            // === testThreeArgMaxOfDoubleResolvesToDouble3Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[21], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 3
                    })
                // Double is preserved end-to-end (unlike Byte, which widens to Int)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.doubleType)
                // Resolves via the Double3 special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .maxOfDouble3)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.doubleType, sema.types.doubleType, sema.types.doubleType])
            }

            // === testThreeArgMinOfDoubleResolvesToDouble3Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[22], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 3
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.doubleType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .minOfDouble3)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.doubleType, sema.types.doubleType, sema.types.doubleType])
            }

            // === testThreeArgMinOfFloatResolvesToFloat3Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[23], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 3
                    })
                // Float is preserved end-to-end (no widening to Double)
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.floatType)
                // Resolves via the Float3 special-call path
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .minOfFloat3)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.floatType, sema.types.floatType, sema.types.floatType])
            }

            // === testRemainingMinOfOverloadsResolveToSyntheticComparisonFunctions ===
            do {
                let expectedCases: [(argCount: Int, returnType: TypeID)] = [
                    (2, sema.types.stringType),
                    (4, sema.types.stringType),
                    (3, sema.types.intType),
                    (5, sema.types.intType),
                    (2, sema.types.uintType),
                    (3, sema.types.uintType),
                ]
                for expected in expectedCases {
                    let callExpr = try #require(lastExprID(in: ast, path: paths[24], ctx: ctx) { exprID, expr in
                            guard case let .call(calleeExpr, _, args, _) = expr,
                                  case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                            else {
                                return false
                            }
                            return interner.resolve(calleeName) == "minOf"
                                && args.count == expected.argCount
                                && sema.bindings.exprTypes[exprID] == expected.returnType
                        })
                    #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                    let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                    let symbol = try #require(sema.symbols.symbol(chosen))
                    #expect(symbol.fqName == [
                        interner.intern("kotlin"),
                        interner.intern("comparisons"),
                        interner.intern("minOf"),
                    ])
                    #expect(sema.bindings.exprTypes[callExpr] == expected.returnType)
                }
            }

            // === testTwoArgMaxOfLongResolvesToLong2Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[25], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 2
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.longType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .maxOfLong)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.longType, sema.types.longType])
            }

            // === testTwoArgMinOfLongResolvesToLong2Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[26], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 2
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.longType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == .minOfLong)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.longType, sema.types.longType])
            }

            // === testTwoArgMinOfULongResolvesToULongOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[27], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 2
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.ulongType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.ulongType, sema.types.ulongType])
                #expect(sig.returnType == sema.types.ulongType)
            }

            // === testThreeArgMinOfULongResolvesToULongOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[28], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 3
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.ulongType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.ulongType, sema.types.ulongType, sema.types.ulongType])
                #expect(sig.returnType == sema.types.ulongType)
            }

            // === testVarargMinOfULongResolvesToVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[29], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 4
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.ulongType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.ulongType, sema.types.ulongType])
                #expect(sig.returnType == sema.types.ulongType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

            // === testVarargMinOfFloatResolvesToVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[30], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 4
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.floatType)
                // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.floatType, sema.types.floatType])
                #expect(sig.returnType == sema.types.floatType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

            // === testVarargMaxOfLongResolvesToVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[31], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "maxOf" && args.count == 4
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.longType)
                // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.longType, sema.types.longType])
                #expect(sig.returnType == sema.types.longType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

            // === testVarargMinOfLongResolvesToVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[32], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 4
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.longType)
                // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.longType, sema.types.longType])
                #expect(sig.returnType == sema.types.longType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

            // === testTwoArgMinOfUShortResolvesToUShort2Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[33], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 2
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.ushortType)
                // Unsigned overloads are not mapped to a special-call kind; lowered via the primitive path.
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.ushortType, sema.types.ushortType])
                #expect(sig.returnType == sema.types.ushortType)
            }

            // === testThreeArgMinOfUShortResolvesToUShort3Overload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[34], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 3
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.ushortType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.ushortType, sema.types.ushortType, sema.types.ushortType])
                #expect(sig.returnType == sema.types.ushortType)
            }

            // === testVarargMinOfUShortResolvesToVarargOverload ===
            do {
                let callExpr = try #require(lastExprID(in: ast, path: paths[35], ctx: ctx) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else { return false }
                        return interner.resolve(calleeName) == "minOf" && args.count == 4
                    })
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.ushortType)
                #expect(sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil)
                let chosen = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosen))
                #expect(symbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("minOf"),
                ])
                let sig = try #require(sema.symbols.functionSignature(for: chosen))
                #expect(sig.parameterTypes == [sema.types.ushortType, sema.types.ushortType])
                #expect(sig.returnType == sema.types.ushortType)
                #expect(sig.valueParameterIsVararg == [false, true])
            }

        }
    }
}
#endif
