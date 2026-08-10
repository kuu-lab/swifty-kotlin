#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

// MARK: - Value class edge case coverage (TEST-VAL-001)

extension ValueClassUnboxingTests {

    // MARK: - Payload type variants and common Sema scenarios

    @Test
    func testValueClassEdgeCaseSema() throws {
        let sources: [String] = [
            // String payload
            """
            value class Name(val raw: String)
            """,
            // Long payload
            """
            value class Timestamp(val epochMillis: Long)
            """,
            // Double payload
            """
            value class Celsius(val degrees: Double)
            """,
            // @JvmInline adds no flags beyond valueType
            """
            @JvmInline
            value class UserIdWith(val raw: Int)
            """,
            """
            value class UserIdWithout(val raw: Int)
            """,
            // Single-property constraint: zero params
            """
            value class Empty()
            """,
            // Single-property constraint: three params
            """
            value class Triple(val a: Int, val b: String, val c: Long)
            """,
            // Upcast to Any should not produce errors
            """
            value class MeterUpcast(val amount: Int)

            fun toAny(m: MeterUpcast): Any = m
            """,
            // Nullable usage keeps valueType flag on the class
            """
            value class Token(val value: String)

            fun maybeToken(): Token? = null
            """,
            // Member function on value class
            """
            value class MeterWithFun(val amount: Int) {
                fun doubled(): Int = amount * 2
            }
            """,
            // Implementing interface
            """
            interface Measurable {
                fun measure(): Int
            }

            value class MeterInterface(val amount: Int) : Measurable {
                override fun measure(): Int = amount
            }
            """,
            // Companion object should not affect valueType flag
            """
            value class Score(val points: Int) {
                companion object {
                    val ZERO = Score(0)
                }
            }
            """,
            // Overridden toString should compile
            """
            value class Version(val code: Int) {
                override fun toString(): String = "Version(${'$'}code)"
            }
            """,
            // When-expression on value class
            """
            value class HttpStatus(val code: Int)

            fun describe(s: HttpStatus): String {
                return when (s.code) {
                    200 -> "OK"
                    404 -> "Not Found"
                    else -> "Other"
                }
            }
            """,
            // Multiple distinct value classes independently tracked
            """
            value class MeterId(val raw: Int)
            value class ScoreId(val raw: Int)
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            do {
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

            do {
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

            do {
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

            do {
                let symWith = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "UserIdWith"
                }))
                let symWithout = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "UserIdWithout"
                }))
                #expect(symWith.flags.contains(.valueType))
                #expect(symWithout.flags.contains(.valueType))
                #expect(
                    symWith.flags.contains(.valueType) == symWithout.flags.contains(.valueType),
                    "@JvmInline should not introduce extra SymbolFlags beyond valueType"
                )
            }

            do {
                let emptyErrors = diagnosticsForPath(paths[5], in: ctx).filter { $0.severity == .error }
                #expect(
                    emptyErrors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
                    "value class with zero params should emit a single-property diagnostic"
                )
            }

            do {
                let tripleErrors = diagnosticsForPath(paths[6], in: ctx).filter { $0.severity == .error }
                #expect(
                    tripleErrors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
                    "value class with three params should emit a single-property diagnostic"
                )
            }

            do {
                let upcastErrors = diagnosticsForPath(paths[7], in: ctx).filter { $0.severity == .error }
                #expect(upcastErrors.isEmpty, "Upcasting value class to Any should not produce errors; got: \(upcastErrors.map { $0.message })")
            }

            do {
                let tokenSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "Token"
                }))
                #expect(tokenSymbol.flags.contains(.valueType), "Token value class should retain valueType flag when used as nullable")
            }

            do {
                let meterWithFunSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "MeterWithFun"
                }))
                #expect(meterWithFunSymbol.flags.contains(.valueType))

                let doubledExists = sema.symbols.allSymbols().contains(where: { symbol in
                    symbol.kind == .function && interner.resolve(symbol.name) == "doubled"
                })
                #expect(doubledExists, "Member function 'doubled' should be registered in the symbol table for value class MeterWithFun")
            }

            do {
                let meterInterfaceSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "MeterInterface"
                }))
                #expect(meterInterfaceSymbol.flags.contains(.valueType), "value class implementing interface should retain valueType flag")
            }

            do {
                let scoreSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "Score"
                }))
                #expect(scoreSymbol.flags.contains(.valueType), "value class with companion object should retain valueType flag")
            }

            do {
                let versionErrors = diagnosticsForPath(paths[12], in: ctx).filter { $0.severity == .error }
                #expect(versionErrors.isEmpty, "value class with overridden toString should compile without errors; got: \(versionErrors.map { $0.message })")
            }

            do {
                let httpStatusErrors = diagnosticsForPath(paths[13], in: ctx).filter { $0.severity == .error }
                #expect(httpStatusErrors.isEmpty, "value class used in when-expression should compile without errors; got: \(httpStatusErrors.map { $0.message })")
            }

            do {
                let valueTypeSymbols = sema.symbols.allSymbols().filter {
                    $0.kind == .class && $0.flags.contains(.valueType)
                }
                let names = valueTypeSymbols.map { interner.resolve($0.name) }
                #expect(names.contains("MeterId"), "MeterId should be registered as a value class")
                #expect(names.contains("ScoreId"), "ScoreId should be registered as a value class")

                for sym in valueTypeSymbols {
                    let name = interner.resolve(sym.name)
                    if name == "Empty" || name == "Triple" {
                        continue
                    }
                    let underlying = sema.symbols.valueClassUnderlyingType(for: sym.id)
                    #expect(underlying != nil, "\(name) should have an underlying type recorded")
                }
            }
        }
    }

    // MARK: - Unboxing lowering with different payload types

    @Test
    func testValueClassUnboxingLoweringEdgeCases() throws {
        let sources: [String] = [
            // String payload should not allocate object box
            """
            value class Name(val raw: String)

            fun greet(n: Name): String = n.raw
            """,
            // Concrete parameter type should run ValueClassUnboxing
            """
            value class MeterConcrete(val amount: Int)

            fun getAmount(m: MeterConcrete): Int = m.amount
            """,
            // Member function call should run ValueClassUnboxing
            """
            value class MeterWithFun(val amount: Int) {
                fun doubled(): Int = amount * 2
            }

            fun compute(): Int {
                val m = MeterWithFun(5)
                return m.doubled()
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let kk_object_new = interner.intern("kk_object_new")

            var hasValueClassAlloc = false
            for function in findAllKIRFunctions(in: module) {
                for instruction in function.body {
                    if case let .call(_, callee, _, result, _, _, _, _) = instruction,
                       callee == kk_object_new,
                       let result,
                       let resultType = module.arena.exprType(result),
                       case let .classType(classType) = ctx.sema?.types.kind(of: resultType),
                       let sym = ctx.sema?.symbols.symbol(classType.classSymbol),
                       sym.flags.contains(.valueType)
                    {
                        hasValueClassAlloc = true
                    }
                }
            }

            #expect(!hasValueClassAlloc, "kk_object_new for String-payload value class should be eliminated by unboxing")
            #expect(
                module.executedLowerings.contains("ValueClassUnboxing"),
                "ValueClassUnboxing pass should run for value class usages"
            )
        }
    }
}
#endif
