#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ComparisonSyntheticTopLevelTests {
    @Test
    func testMaxOfAndMinOfResolveToSourceBackedComparisonFunctions() throws {
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
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
                        guard case let .call(calleeExpr, _, _, _) = expr,
                              case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                        else {
                            return false
                        }
                        return interner.resolve(calleeName) == name
                    })

                let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
                let symbol = try #require(sema.symbols.symbol(chosenCallee))
                #expect(symbol.fqName.map { interner.resolve($0) } == ["kotlin", "comparisons", expectedResolvedName], "Expected \(name) to resolve to kotlin.comparisons.\(expectedResolvedName)")
                #expect(sema.symbols.externalLinkName(for: chosenCallee) == expectedLink, "Expected \(name) to link to \(expectedLink)")
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, args, _, _) = expr,
                          args.count == 2,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "compareByDescending"
                })

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_from_comparator_selector_descending")
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, args, _, _) = expr,
                          args.count == 2,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == "compareBy"
                })

            let chosenCallee = try #require(sema.bindings.callBinding(for: callExpr)?.chosenCallee)
            #expect(sema.symbols.externalLinkName(for: chosenCallee) == "kk_comparator_from_comparator_selector")
        }
    }

    // STDLIB-614: 3-arg minOf / maxOf overloads
    @Test
    func testThreeArgMaxOfMinOfResolveToSourceBackedComparisonFunctions() throws {
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
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
                let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    @Test
    func testRemainingMaxOfOverloadsResolveToSourceBackedComparisonFunctions() throws {
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
                let callExpr = try #require(lastExprID(in: ast) { exprID, expr in
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
    }

    // STDLIB-COMP-FN-051: minOf unsigned overloads (UByte, UShort, UInt, ULong) resolve to source-backed comparison functions
    @Test
    func testRemainingMinOfUnsignedOverloadsResolveToSourceBackedComparisonFunctions() throws {
        let source = """
        fun sample() {
            val unsignedMin2 = minOf(1u, 4000000000u)
            val unsignedMin3 = minOf(1u, 3u, 4000000000u)
            println(unsignedMin2)
            println(unsignedMin3)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let expectedCases: [(argCount: Int, returnType: TypeID)] = [
                (2, sema.types.uintType),
                (3, sema.types.uintType),
            ]

            for expected in expectedCases {
                let callExpr = try #require(lastExprID(in: ast) { exprID, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-015: maxOf(Float, Float, Float) — Float is preserved (no widening to Double)
    @Test
    func testThreeArgMaxOfFloatResolvesToFloat3Overload() throws {
        let source = """
        fun sample(a: Float, b: Float, c: Float): Float = maxOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-050: minOf(UByte, UByte): UByte and related unsigned overloads
    @Test
    func testRemainingMinOfOverloadsResolveToSourceBackedComparisonFunctions() throws {
        let source = """
        fun sample() {
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
                let callExpr = try #require(lastExprID(in: ast) { exprID, expr in
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
    }

    // STDLIB-COMP-FN-020: maxOf(Long, Long) — 2-arg Long overload
    @Test
    func testTwoArgMaxOfLongResolvesToLong2Overload() throws {
        let source = """
        fun sample(a: Long, b: Long): Long = maxOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-044: minOf(Long, Long) — 2-arg Long overload
    @Test
    func testTwoArgMinOfLongResolvesToLong2Overload() throws {
        let source = """
        fun sample(a: Long, b: Long): Long = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-052: minOf(ULong, ULong) — 2-arg ULong resolves via remaining path (no special-call kind)
    @Test
    func testTwoArgMinOfULongResolvesToULongOverload() throws {
        let source = """
        fun sample(a: ULong, b: ULong): ULong = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-052: minOf(ULong, ULong, ULong) — 3-arg ULong resolves via remaining path
    @Test
    func testThreeArgMinOfULongResolvesToULongOverload() throws {
        let source = """
        fun sample(a: ULong, b: ULong, c: ULong): ULong = minOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-052: minOf(a: ULong, vararg other: ULong) — 4+ args resolve to vararg overload
    @Test
    func testVarargMinOfULongResolvesToVarargOverload() throws {
        let source = """
        fun sample(): ULong = minOf(5uL, 2uL, 8uL, 1uL)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-040: minOf(a: Float, vararg other: Float) — 4+ args resolve to the vararg overload
    @Test
    func testVarargMinOfFloatResolvesToVarargOverload() throws {
        let source = """
        fun sample(): Float = minOf(5.0f, 2.0f, 8.0f, 1.0f)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-046: minOf(a: Long, vararg other: Long) — 4+ args resolve to the vararg overload
    @Test
    func testVarargMinOfLongResolvesToVarargOverload() throws {
        let source = """
        fun sample(): Long = minOf(5L, 2L, 8L, 1L)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-053: minOf(UShort, UShort): UShort — 2-arg overload
    @Test
    func testTwoArgMinOfUShortResolvesToUShort2Overload() throws {
        let source = """
        fun sample(a: UShort, b: UShort): UShort = minOf(a, b)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-053: minOf(UShort, UShort, UShort): UShort — 3-arg overload
    @Test
    func testThreeArgMinOfUShortResolvesToUShort3Overload() throws {
        let source = """
        fun sample(a: UShort, b: UShort, c: UShort): UShort = minOf(a, b, c)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
    }

    // STDLIB-COMP-FN-053: minOf(a: UShort, vararg other: UShort) — 4+ arg vararg overload
    @Test
    func testVarargMinOfUShortResolvesToVarargOverload() throws {
        let source = """
        fun sample(a: UShort, b: UShort, c: UShort, d: UShort): UShort = minOf(a, b, c, d)
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try #require(ctx.ast)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            let callExpr = try #require(lastExprID(in: ast) { _, expr in
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
#endif
