@testable import CompilerCore
import Foundation
import XCTest

final class ComparisonSyntheticTopLevelTests: XCTestCase {
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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try XCTUnwrap(
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
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfInt : .minOfInt)
                let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
                XCTAssertEqual(symbol.fqName, [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern(name),
                ])
            }
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            for (name, expectedResolvedName, expectedLink) in [
                ("compareBy", "compareByPrimitive", "kk_comparator_from_selector_primitive"),
                ("compareByDescending", "compareByDescendingPrimitive", "kk_comparator_from_selector_primitive_descending"),
            ] {
                let callExpr = try XCTUnwrap(
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

                let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosenCallee))
                XCTAssertEqual(
                    symbol.fqName.map { interner.resolve($0) },
                    ["kotlin", "comparisons", expectedResolvedName],
                    "Expected \(name) to resolve to kotlin.comparisons.\(expectedResolvedName)"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedLink,
                    "Expected \(name) to link to \(expectedLink)"
                )
            }
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
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

            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_from_comparator_selector_descending"
            )
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
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

            let chosenCallee = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: chosenCallee),
                "kk_comparator_from_comparator_selector"
            )
        }
    }

    // STDLIB-614: 3-arg minOf / maxOf overloads
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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try XCTUnwrap(
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
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfInt3 : .minOfInt3)
                let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
                XCTAssertEqual(symbol.fqName, [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern(name),
                ])
                // Verify 3-param signature
                let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
                XCTAssertEqual(sig.parameterTypes.count, 3)
            }
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try XCTUnwrap(
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
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.longType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfLong3 : .minOfLong3)
            }
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            for name in ["maxOf", "minOf"] {
                let callExpr = try XCTUnwrap(
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
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.doubleType)
                let kind = sema.bindings.stdlibSpecialCallKind(for: callExpr)
                XCTAssertEqual(kind, name == "maxOf" ? .maxOfDouble3 : .minOfDouble3)
            }
        }
    }

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

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
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
                let callExpr = try XCTUnwrap(
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
                XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
                let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
                XCTAssertEqual(symbol.fqName, [
                    interner.intern("kotlin"),
                    interner.intern("comparisons"),
                    interner.intern("maxOf"),
                ])
                XCTAssertEqual(sema.bindings.exprTypes[callExpr], expected.returnType)
            }
        }
    }

    // STDLIB-COMP-FN-009: maxOf(Byte, Byte, Byte) — Byte resolves to Int internally
    func testThreeArgMaxOfByteResolvesToInt3Overload() throws {
        let source = """
        fun sample(a: Byte, b: Byte, c: Byte): Byte = maxOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 3
                },
                "Expected 3-arg maxOf call with Byte arguments"
            )

            // Byte maps to Int internally, so the result type is Int
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
            // Resolves via the Int3 special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .maxOfInt3)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType, sema.types.intType])
        }
    }

    // STDLIB-COMP-FN-024: maxOf(Short, Short, Short) — Short resolves to Int internally
    func testThreeArgMaxOfShortResolvesToInt3Overload() throws {
        let source = """
        fun sample(a: Short, b: Short, c: Short): Short = maxOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 3
                },
                "Expected 3-arg maxOf call with Short arguments"
            )

            // Short maps to Int internally, so the result type is Int
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
            // Resolves via the Int3 special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .maxOfInt3)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType, sema.types.intType])
        }
    }

    // STDLIB-COMP-FN-041: minOf(Int, Int) — 2-arg Int overload
    func testTwoArgMinOfIntResolvesToInt2Overload() throws {
        let source = """
        fun sample(a: Int, b: Int): Int = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Int arguments"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
            // Resolves via the Int 2-arg special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .minOfInt)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType])
        }
    }

    // STDLIB-COMP-FN-043: minOf(a: Int, vararg other: Int) — 4+ args resolve to the vararg overload
    func testVarargMinOfIntResolvesToVarargOverload() throws {
        let source = """
        fun sample(): Int = minOf(5, 2, 8, 1)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 4
                },
                "Expected 4-arg minOf call"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
            // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
            XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])

            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType])
            XCTAssertEqual(sig.returnType, sema.types.intType)
            XCTAssertEqual(sig.valueParameterIsVararg, [false, true])
        }
    }

    // STDLIB-COMP-FN-032: minOf(Byte, Byte) — Byte resolves to Int internally
    func testTwoArgMinOfByteResolvesToInt2Overload() throws {
        let source = """
        fun sample(a: Byte, b: Byte): Byte = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Byte arguments"
            )

            // Byte maps to Int internally, so the result type is Int
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
            // Resolves via the Int 2-arg special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .minOfInt)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType])
        }
    }

    // STDLIB-COMP-FN-034: minOf(Byte, Byte, ..., Byte) — Byte widens to Int, vararg Int overload resolves
    func testVarargMinOfByteResolvesToIntVarargOverload() throws {
        let source = """
        fun sample(a: Byte, b: Byte, c: Byte, d: Byte): Byte = minOf(a, b, c, d)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 4
                },
                "Expected 4-arg minOf call with Byte arguments"
            )

            // Byte maps to Int internally, so the result type is Int
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
            // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
            XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType])
            XCTAssertEqual(sig.returnType, sema.types.intType)
            XCTAssertEqual(sig.valueParameterIsVararg, [false, true])
        }
    }

    // STDLIB-COMP-FN-010: maxOf(Byte, Byte, ..., Byte) — Byte widens to Int, vararg Int overload resolves
    func testVarargMaxOfByteResolvesToIntVarargOverload() throws {
        let source = """
        fun sample(a: Byte, b: Byte, c: Byte, d: Byte): Byte = maxOf(a, b, c, d)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 4
                },
                "Expected 4-arg maxOf call with Byte arguments"
            )

            // Byte maps to Int internally, so the result type is Int
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.intType)
            // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
            XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.intType, sema.types.intType])
            XCTAssertEqual(sig.returnType, sema.types.intType)
            XCTAssertEqual(sig.valueParameterIsVararg, [false, true])
        }
    }

    // STDLIB-COMP-FN-014: maxOf(Float, Float) — 2-arg Float overload
    func testTwoArgMaxOfFloatResolvesToFloat2Overload() throws {
        let source = """
        fun sample(a: Float, b: Float): Float = maxOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 2
                },
                "Expected 2-arg maxOf call with Float arguments"
            )

            // Float is preserved end-to-end (no widening to Double)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.floatType)
            // Resolves via the Float 2-arg special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .maxOfFloat)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.floatType, sema.types.floatType])
        }
    }

    // STDLIB-COMP-FN-038: minOf(Float, Float) — 2-arg Float overload
    func testTwoArgMinOfFloatResolvesToFloat2Overload() throws {
        let source = """
        fun sample(a: Float, b: Float): Float = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Float arguments"
            )

            // Float is preserved end-to-end (no widening to Double)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.floatType)
            // Resolves via the Float 2-arg special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .minOfFloat)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.floatType, sema.types.floatType])
        }
    }

    // STDLIB-COMP-FN-011: maxOf(Double, Double) — Double is preserved (no widening)
    func testTwoArgMaxOfDoubleResolvesToDoubleOverload() throws {
        let source = """
        fun sample(a: Double, b: Double): Double = maxOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 2
                },
                "Expected 2-arg maxOf call with Double arguments"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.doubleType)
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .maxOfDouble)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.doubleType, sema.types.doubleType])
        }
    }

    // STDLIB-COMP-FN-035: minOf(Double, Double) — Double is preserved (no widening)
    func testTwoArgMinOfDoubleResolvesToDoubleOverload() throws {
        let source = """
        fun sample(a: Double, b: Double): Double = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 2
                },
                "Expected 2-arg minOf call with Double arguments"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.doubleType)
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .minOfDouble)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.doubleType, sema.types.doubleType])
        }
    }

    // STDLIB-COMP-FN-012: maxOf(Double, Double, Double) — Double is preserved (no widening)
    func testThreeArgMaxOfDoubleResolvesToDouble3Overload() throws {
        let source = """
        fun sample(a: Double, b: Double, c: Double): Double = maxOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 3
                },
                "Expected 3-arg maxOf call with Double arguments"
            )

            // Double is preserved end-to-end (unlike Byte, which widens to Int)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.doubleType)
            // Resolves via the Double3 special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .maxOfDouble3)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.doubleType, sema.types.doubleType, sema.types.doubleType])
        }
    }

    // STDLIB-COMP-FN-036: minOf(Double, Double, Double) — Double is preserved (no widening)
    func testThreeArgMinOfDoubleResolvesToDouble3Overload() throws {
        let source = """
        fun sample(a: Double, b: Double, c: Double): Double = minOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 3
                },
                "Expected 3-arg minOf call with Double arguments"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.doubleType)
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .minOfDouble3)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.doubleType, sema.types.doubleType, sema.types.doubleType])
        }
    }

    // STDLIB-COMP-FN-039: minOf(Float, Float, Float) — Float is preserved (no widening to Double)
    func testThreeArgMinOfFloatResolvesToFloat3Overload() throws {
        let source = """
        fun sample(a: Float, b: Float, c: Float): Float = minOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 3
                },
                "Expected 3-arg minOf call with Float arguments"
            )

            // Float is preserved end-to-end (no widening to Double)
            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.floatType)
            // Resolves via the Float3 special-call path
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .minOfFloat3)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.floatType, sema.types.floatType, sema.types.floatType])
        }
    }

    // STDLIB-COMP-FN-020: maxOf(Long, Long) — 2-arg Long overload
    func testTwoArgMaxOfLongResolvesToLong2Overload() throws {
        let source = """
        fun sample(a: Long, b: Long): Long = maxOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 2
                },
                "Expected 2-arg maxOf call with Long arguments"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.longType)
            XCTAssertEqual(sema.bindings.stdlibSpecialCallKind(for: callExpr), .maxOfLong)
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])
            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.longType, sema.types.longType])
        }
    }

    // STDLIB-COMP-FN-040: minOf(a: Float, vararg other: Float) — 4+ args resolve to the vararg overload
    func testVarargMinOfFloatResolvesToVarargOverload() throws {
        let source = """
        fun sample(): Float = minOf(5.0f, 2.0f, 8.0f, 1.0f)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "minOf" && args.count == 4
                },
                "Expected 4-arg minOf call"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.floatType)
            // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
            XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("minOf"),
            ])

            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.floatType, sema.types.floatType])
            XCTAssertEqual(sig.returnType, sema.types.floatType)
            XCTAssertEqual(sig.valueParameterIsVararg, [false, true])
        }
    }

    // STDLIB-COMP-FN-022: maxOf(a: Long, vararg other: Long) — 4+ args resolve to the vararg overload
    func testVarargMaxOfLongResolvesToVarargOverload() throws {
        let source = """
        fun sample(): Long = maxOf(5L, 2L, 8L, 1L)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let interner = ctx.interner

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, args, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else { return false }
                    return interner.resolve(calleeName) == "maxOf" && args.count == 4
                },
                "Expected 4-arg maxOf call"
            )

            XCTAssertEqual(sema.bindings.exprTypes[callExpr], sema.types.longType)
            // The vararg overload is lowered inline, not via a fixed-arity special-call kind.
            XCTAssertNil(sema.bindings.stdlibSpecialCallKind(for: callExpr))
            let chosen = try XCTUnwrap(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            let symbol = try XCTUnwrap(sema.symbols.symbol(chosen))
            XCTAssertEqual(symbol.fqName, [
                interner.intern("kotlin"),
                interner.intern("comparisons"),
                interner.intern("maxOf"),
            ])

            let sig = try XCTUnwrap(sema.symbols.functionSignature(for: chosen))
            XCTAssertEqual(sig.parameterTypes, [sema.types.longType, sema.types.longType])
            XCTAssertEqual(sig.returnType, sema.types.longType)
            XCTAssertEqual(sig.valueParameterIsVararg, [false, true])
        }
    }
}
