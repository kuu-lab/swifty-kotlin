#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ComparisonSyntheticTopLevelTests {
    private func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }

    @Test
    func testMaxOfAndMinOfResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample(): Int {
            val hi = maxOf(3, 7)
            val lo = minOf(3, 7)
            return hi - lo
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try #require(
                    firstExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, _, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name
                    },
                    "Expected call to \(name)"
                )
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
    }

    @Test
    func testCompareByAndCompareByDescendingResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample() {
            val ascending = compareBy<Int> { it % 10 }
            val descending = compareByDescending<Int> { it % 10 }
            println(listOf(231, 114, 123).sortedWith(ascending))
            println(listOf(231, 114, 123).sortedWith(descending))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for (name, expectedResolvedName, expectedLink) in [
                ("compareBy", "compareByPrimitive", "kk_comparator_from_selector_primitive"),
                ("compareByDescending", "compareByDescendingPrimitive", "kk_comparator_from_selector_primitive_descending"),
            ] {
                let callExpr = try #require(
                    firstExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, _, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name
                    },
                    "Expected call to \(name)"
                )

                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                #expect(
                    symbol.fqName.map { interner.resolve($0) } == ["kotlin", "comparisons", expectedResolvedName],
                    "Expected \(name) to resolve to kotlin.comparisons.\(expectedResolvedName)"
                )
                #expect(
                    sema.symbols.externalLinkName(for: chosenCallee) == expectedLink,
                    "Expected \(name) to link to \(expectedLink)"
                )
            }
        }
    }

    @Test
    func testCompareByDescendingComparatorSelectorResolvesToSyntheticFunction() throws {
        let source = """
        fun sample() {
            val cmp = compareByDescending<String, Int>(compareBy<Int> { it }) { it.length }
            println(listOf("pear", "fig", "apple").sortedWith(cmp))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, args, _, _) = expr,
                          args.count == 2,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "compareByDescending"
                },
                "Expected compareByDescending(comparator, selector) call"
            )

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_from_comparator_selector_descending"
            )
        }
    }

    @Test
    func testCompareByComparatorSelectorResolvesToSyntheticFunction() throws {
        let source = """
        fun sample() {
            val cmp = compareBy<String, Int>(compareBy<Int> { it }) { it.length }
            println(listOf("pear", "fig", "apple").sortedWith(cmp))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, args, _, _) = expr,
                          args.count == 2,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "compareBy"
                },
                "Expected compareBy(comparator, selector) call"
            )

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_from_comparator_selector"
            )
        }
    }

    // STDLIB-614: 3-arg minOf / maxOf overloads
    @Test
    func testThreeArgMaxOfMinOfResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample(): Int {
            val hi = maxOf(1, 5, 3)
            val lo = minOf(1, 5, 3)
            return hi - lo
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try #require(
                    firstExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name && args.count == 3
                    },
                    "Expected 3-arg call to \(name)"
                )
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
    }

    @Test
    func testThreeArgMaxOfMinOfLongOverload() throws {
        let source = """
        fun sample(): Long {
            val hi = maxOf(1L, 5L, 3L)
            val lo = minOf(1L, 5L, 3L)
            return hi - lo
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try #require(
                    firstExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name && args.count == 3
                    },
                    "Expected 3-arg call to \(name)"
                )
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.longType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                #expect(kind == (name == "maxOf" ? .maxOfLong3 : .minOfLong3))
            }
        }
    }

    @Test
    func testThreeArgMaxOfMinOfDoubleOverload() throws {
        let source = """
        fun sample(): Double {
            val hi = maxOf(1.0, 5.0, 3.0)
            val lo = minOf(1.0, 5.0, 3.0)
            return hi - lo
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try #require(
                    firstExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name && args.count == 3
                    },
                    "Expected 3-arg call to \(name)"
                )
                #expect(sema.bindings.exprTypes[callExpr] == sema.types.doubleType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                #expect(kind == (name == "maxOf" ? .maxOfDouble3 : .minOfDouble3))
            }
        }
    }

    @Test
    func testRemainingMaxOfOverloadsResolveToSyntheticComparisonFunctions() throws {
        let source = """
        fun sample() {
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
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let expectedCases: [(argCount: Int, returnType: TypeID)] = [
                (2, sema.types.stringType),
                (4, sema.types.stringType),
                (3, sema.types.intType),
                (5, sema.types.intType),
                (2, sema.types.uintType),
                (3, sema.types.uintType),
            ]

            for expected in expectedCases {
                let callExpr = try #require(
                    firstExprID(in: ast) { exprID, expr in
                        guard case let .call(calleeExpr, _, args, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == "maxOf"
                            && args.count == expected.argCount
                            && sema.bindings.exprTypes[exprID] == expected.returnType
                    },
                    "Expected maxOf(\(expected.argCount) args) to resolve"
                )
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
    }

    // STDLIB-COMP-FN-009: maxOf(Byte, Byte, Byte) — Byte resolves to Int internally
    @Test
    func testThreeArgMaxOfByteResolvesToInt3Overload() throws {
        let source = """
        fun sample(a: Byte, b: Byte, c: Byte): Byte = maxOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 3
                },
                "Expected 3-arg maxOf call with Byte arguments"
            )

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
    }

    // STDLIB-COMP-FN-024: maxOf(Short, Short, Short) — Short resolves to Int internally
    @Test
    func testThreeArgMaxOfShortResolvesToInt3Overload() throws {
        let source = """
        fun sample(a: Short, b: Short, c: Short): Short = maxOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 3
                },
                "Expected 3-arg maxOf call with Short arguments"
            )

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
    }

    // STDLIB-COMP-FN-041: minOf(Int, Int) — 2-arg Int overload
    @Test
    func testTwoArgMinOfIntResolvesToInt2Overload() throws {
        let source = """
        fun sample(a: Int, b: Int): Int = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Int arguments"
            )

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
    }

    // STDLIB-COMP-FN-043: minOf(a: Int, vararg other: Int) — 4+ args resolve to the vararg overload
    @Test
    func testVarargMinOfIntResolvesToVarargOverload() throws {
        let source = """
        fun sample(): Int = minOf(5, 2, 8, 1)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 4
                },
                "Expected 4-arg minOf call"
            )

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
    }

    // STDLIB-COMP-FN-032: minOf(Byte, Byte) — Byte resolves to Int internally
    @Test
    func testTwoArgMinOfByteResolvesToInt2Overload() throws {
        let source = """
        fun sample(a: Byte, b: Byte): Byte = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Byte arguments"
            )

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
    }

    // STDLIB-COMP-FN-034: minOf(Byte, Byte, ..., Byte) — Byte widens to Int, vararg Int overload resolves
    @Test
    func testVarargMinOfByteResolvesToIntVarargOverload() throws {
        let source = """
        fun sample(a: Byte, b: Byte, c: Byte, d: Byte): Byte = minOf(a, b, c, d)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 4
                },
                "Expected 4-arg minOf call with Byte arguments"
            )

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
    }

    // STDLIB-COMP-FN-010: maxOf(Byte, Byte, ..., Byte) — Byte widens to Int, vararg Int overload resolves
    @Test
    func testVarargMaxOfByteResolvesToIntVarargOverload() throws {
        let source = """
        fun sample(a: Byte, b: Byte, c: Byte, d: Byte): Byte = maxOf(a, b, c, d)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 4
                },
                "Expected 4-arg maxOf call with Byte arguments"
            )

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
    }

    // STDLIB-COMP-FN-014: maxOf(Float, Float) — 2-arg Float overload
    @Test
    func testTwoArgMaxOfFloatResolvesToFloat2Overload() throws {
        let source = """
        fun sample(a: Float, b: Float): Float = maxOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 2
                },
                "Expected 2-arg maxOf call with Float arguments"
            )

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
    }

    // STDLIB-COMP-FN-038: minOf(Float, Float) — 2-arg Float overload
    @Test
    func testTwoArgMinOfFloatResolvesToFloat2Overload() throws {
        let source = """
        fun sample(a: Float, b: Float): Float = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Float arguments"
            )

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
    }

    // STDLIB-COMP-FN-011: maxOf(Double, Double) — Double is preserved (no widening)
    @Test
    func testTwoArgMaxOfDoubleResolvesToDoubleOverload() throws {
        let source = """
        fun sample(a: Double, b: Double): Double = maxOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 2
                },
                "Expected 2-arg maxOf call with Double arguments"
            )

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
    }

    // STDLIB-COMP-FN-035: minOf(Double, Double) — Double is preserved (no widening)
    @Test
    func testTwoArgMinOfDoubleResolvesToDoubleOverload() throws {
        let source = """
        fun sample(a: Double, b: Double): Double = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Double arguments"
            )

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
    }

    // STDLIB-COMP-FN-012: maxOf(Double, Double, Double) — Double is preserved (no widening)
    @Test
    func testThreeArgMaxOfDoubleResolvesToDouble3Overload() throws {
        let source = """
        fun sample(a: Double, b: Double, c: Double): Double = maxOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 3
                },
                "Expected 3-arg maxOf call with Double arguments"
            )

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
    }

    // STDLIB-COMP-FN-036: minOf(Double, Double, Double) — Double is preserved (no widening)
    @Test
    func testThreeArgMinOfDoubleResolvesToDouble3Overload() throws {
        let source = """
        fun sample(a: Double, b: Double, c: Double): Double = minOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 3
                },
                "Expected 3-arg minOf call with Double arguments"
            )

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
    }

    // STDLIB-COMP-FN-039: minOf(Float, Float, Float) — Float is preserved (no widening to Double)
    @Test
    func testThreeArgMinOfFloatResolvesToFloat3Overload() throws {
        let source = """
        fun sample(a: Float, b: Float, c: Float): Float = minOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 3
                },
                "Expected 3-arg minOf call with Float arguments"
            )

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
    }

    // STDLIB-COMP-FN-022: maxOf(a: Long, vararg other: Long) — 4+ args resolve to the vararg overload
    @Test
    func testVarargMaxOfLongResolvesToVarargOverload() throws {
        let source = """
        fun sample(): Long = maxOf(5L, 2L, 8L, 1L)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 4
                },
                "Expected 4-arg maxOf call"
            )

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
    }
}
#endif
