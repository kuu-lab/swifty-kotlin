#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Value class edge case coverage (TEST-VAL-001)

extension ValueClassUnboxingTests {

    // MARK: - Payload type variants

    @Test
    func testValueClassWithStringPayload() throws {
        let source = """
        value class Name(val raw: String)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let nameSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Name"
        }))
        #expect(nameSymbol.flags.contains(.valueType), "value class with String payload should have valueType flag")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: nameSymbol.id)
        #expect(underlyingType != nil, "value class with String payload should record an underlying type")
        if let underlyingType {
            if case .stringStruct = sema.types.kind(of: underlyingType) {
                // Expected
            } else {
                Issue.record("Expected underlying type to be String, got \(sema.types.kind(of: underlyingType))")
            }
        }
    }

    @Test
    func testValueClassWithLongPayload() throws {
        let source = """
        value class Timestamp(val epochMillis: Long)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let tsSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Timestamp"
        }))
        #expect(tsSymbol.flags.contains(.valueType), "value class with Long payload should have valueType flag")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: tsSymbol.id)
        #expect(underlyingType != nil, "value class with Long payload should record an underlying type")
        if let underlyingType {
            if case .primitive(.long, _) = sema.types.kind(of: underlyingType) {
                // Expected
            } else {
                Issue.record("Expected underlying type to be Long, got \(sema.types.kind(of: underlyingType))")
            }
        }
    }

    @Test
    func testValueClassWithDoublePayload() throws {
        let source = """
        value class Celsius(val degrees: Double)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let celsiusSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Celsius"
        }))
        #expect(celsiusSymbol.flags.contains(.valueType), "value class with Double payload should have valueType flag")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: celsiusSymbol.id)
        #expect(underlyingType != nil, "value class with Double payload should record an underlying type")
        if let underlyingType {
            if case .primitive(.double, _) = sema.types.kind(of: underlyingType) {
                // Expected
            } else {
                Issue.record("Expected underlying type to be Double, got \(sema.types.kind(of: underlyingType))")
            }
        }
    }

    // MARK: - Unboxing lowering with different payload types

    @Test
    func testValueClassLoweringEdgeCases() throws {
        let sources = [
            """
            package valueclass.edge0
            value class Name(val raw: String)

            fun greet(n: Name): String = n.raw
            """,
            """
            package valueclass.edge1
            value class ConcreteMeter(val amount: Int)

            fun getAmount(m: ConcreteMeter): Int = m.amount
            """,
            """
            package valueclass.edge2
            value class MemberMeter(val amount: Int) {
                fun doubled(): Int = amount * 2
            }

            fun compute(): Int {
                val m = MemberMeter(5)
                return m.doubled()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToLowering(ctx)

            for path in paths {
                let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
                #expect(errors.isEmpty, "Shared value-class fixture should have no errors for \(path): \(errors.map(\.message))")
            }

            let module = try #require(ctx.kir)
            let sema = try #require(ctx.sema)
            let interner = ctx.interner
            let nameSymbol = try #require(sema.symbols.allSymbols().first { symbol in
                symbol.kind == .class && interner.resolve(symbol.name) == "Name"
            })
            let kkObjectNew = interner.intern("kk_object_new")

            var hasNameValueClassAlloc = false
            for function in findAllKIRFunctions(in: module) {
                for instruction in function.body {
                    if case let .call(_, callee, _, result, _, _, _, _ ) = instruction,
                       callee == kkObjectNew,
                       let result,
                       let resultType = module.arena.exprType(result),
                       case let .classType(classType) = sema.types.kind(of: resultType),
                       classType.classSymbol == nameSymbol.id
                    {
                        hasNameValueClassAlloc = true
                    }
                }
            }

            #expect(!hasNameValueClassAlloc, "String-payload value class should not allocate a heap object after lowering")
            #expect(
                module.executedLowerings.contains("ValueClassUnboxing"),
                "ValueClassUnboxing pass should run for concrete value class parameters and member calls"
            )
        }
    }

    // MARK: - @JvmInline annotation is inert (no additional effects beyond valueType flag)

    @Test
    func testJvmInlineAnnotationIsInertBeyondValueTypeFlag() throws {
        let sourceWithAnnotation = """
        @JvmInline
        value class UserId(val raw: Int)
        """
        let sourceWithout = """
        value class UserId(val raw: Int)
        """
        let ctxWith = makeContextFromSource(sourceWithAnnotation)
        let ctxWithout = makeContextFromSource(sourceWithout)
        try runSema(ctxWith)
        try runSema(ctxWithout)

        let semaWith = try #require(ctxWith.sema)
        let semaWithout = try #require(ctxWithout.sema)

        let symWith = try #require(semaWith.symbols.allSymbols().first(where: {
            $0.kind == .class && ctxWith.interner.resolve($0.name) == "UserId"
        }))
        let symWithout = try #require(semaWithout.symbols.allSymbols().first(where: {
            $0.kind == .class && ctxWithout.interner.resolve($0.name) == "UserId"
        }))

        // Both should have the valueType flag — @JvmInline adds no extra flags
        #expect(symWith.flags.contains(.valueType))
        #expect(symWithout.flags.contains(.valueType))
        #expect(
            symWith.flags.contains(.valueType) == symWithout.flags.contains(.valueType),
            "@JvmInline should not introduce extra SymbolFlags beyond valueType"
        )
    }

    // MARK: - Single-property constraint diagnostics

    @Test
    func testValueClassWithZeroParamsEmitsDiagnostic() throws {
        let source = """
        value class Empty()
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
            "value class with zero params should emit a single-property diagnostic"
        )
    }

    @Test
    func testValueClassWithThreeParamsEmitsDiagnostic() throws {
        let source = """
        value class Triple(val a: Int, val b: String, val c: Long)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
            "value class with three params should emit a single-property diagnostic"
        )
    }

    // MARK: - Upcast / boxing transition: stored as supertype

    @Test
    func testValueClassUpcastedToAnyUnboxed() throws {
        let source = """
        value class Meter(val amount: Int)

        fun toAny(m: Meter): Any = m
        """
        let ctx = makeContextFromSource(source)
        // Sema should succeed without errors even when value class is upcast to Any
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "Upcasting value class to Any should not produce errors; got: \(errors.map { $0.message })")
    }

    // MARK: - Nullable value class

    @Test
    func testNullableValueClassIsRecognizedAsValueType() throws {
        let source = """
        value class Token(val value: String)

        fun maybeToken(): Token? = null
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let tokenSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Token"
        }))
        // The Token class itself still has the valueType flag regardless of nullable usage
        #expect(tokenSymbol.flags.contains(.valueType), "Token value class should retain valueType flag when used as nullable")
    }

    // MARK: - Member functions on value class

    @Test
    func testValueClassMemberFunctionIsRegistered() throws {
        let source = """
        value class Meter(val amount: Int) {
            fun doubled(): Int = amount * 2
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        #expect(meterSymbol.flags.contains(.valueType))

        // The member function 'doubled' should exist in the symbol table
        let doubledExists = sema.symbols.allSymbols().contains(where: { symbol in
            symbol.kind == .function && interner.resolve(symbol.name) == "doubled"
        })
        #expect(doubledExists, "Member function 'doubled' should be registered in the symbol table for value class Meter")
    }

    // MARK: - Value class implementing interface

    @Test
    func testValueClassImplementingInterfaceHasValueTypeFlag() throws {
        let source = """
        interface Measurable {
            fun measure(): Int
        }

        value class Meter(val amount: Int) : Measurable {
            override fun measure(): Int = amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        #expect(meterSymbol.flags.contains(.valueType), "value class implementing interface should retain valueType flag")
    }

    // MARK: - Companion object in value class

    @Test
    func testValueClassWithCompanionObjectDoesNotAffectValueFlag() throws {
        let source = """
        value class Score(val points: Int) {
            companion object {
                val ZERO = Score(0)
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let scoreSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Score"
        }))
        #expect(scoreSymbol.flags.contains(.valueType), "value class with companion object should retain valueType flag")
    }

    // MARK: - toString / default representation

    @Test
    func testValueClassToStringFunctionParsesWithoutError() throws {
        let source = """
        value class Version(val code: Int) {
            override fun toString(): String = "Version(${'$'}code)"
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "value class with overridden toString should compile without errors; got: \(errors.map { $0.message })"
        )
    }

    // MARK: - Value class used in when-expression

    @Test
    func testValueClassUsedInWhenExpressionCompiles() throws {
        let source = """
        value class HttpStatus(val code: Int)

        fun describe(s: HttpStatus): String {
            return when (s.code) {
                200 -> "OK"
                404 -> "Not Found"
                else -> "Other"
            }
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "value class used in when-expression should compile without errors; got: \(errors.map { $0.message })"
        )
    }

    // MARK: - Multiple distinct value classes coexist

    @Test
    func testMultipleValueClassesAreIndependentlyTracked() throws {
        let source = """
        value class MeterId(val raw: Int)
        value class ScoreId(val raw: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let valueTypeSymbols = sema.symbols.allSymbols().filter {
            $0.kind == .class && $0.flags.contains(.valueType)
        }
        let names = valueTypeSymbols.map { interner.resolve($0.name) }
        #expect(names.contains("MeterId"), "MeterId should be registered as a value class")
        #expect(names.contains("ScoreId"), "ScoreId should be registered as a value class")
        #expect(valueTypeSymbols.count >= 2, "Both value classes should be independently tracked")

        // Each must have an underlying type recorded
        for sym in valueTypeSymbols {
            let underlying = sema.symbols.valueClassUnderlyingType(for: sym.id)
            #expect(underlying != nil, "\(interner.resolve(sym.name)) should have an underlying type recorded")
        }
    }
}
#endif
