#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct ValueClassUnboxingTests {

    // MARK: - Sema-level value class validation

    @Test
    func testValueClassSema() throws {
        let sources: [String] = [
            // Flag and underlying type
            """
            value class Meter(val amount: Int)
            """,
            // @JvmInline value class
            """
            @JvmInline
            value class UserId(val raw: Int)
            """,
            // inline class (legacy keyword)
            """
            inline class LegacyCount(val raw: Int)
            """,
            // Multiple primary constructor parameters diagnostic
            """
            value class BadMultiple(val x: Int, val y: Int)
            """,
            // Secondary constructor diagnostic
            """
            value class BadSecondary(val x: Int) {
                constructor() : this(0)
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)

            let sema = try #require(ctx.sema)
            let interner = ctx.interner

            do {
                let meterSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
                }))
                #expect(meterSymbol.flags.contains(.valueType), "value class should have valueType flag")

                let underlyingType = sema.symbols.valueClassUnderlyingType(for: meterSymbol.id)
                #expect(underlyingType != nil, "value class should have an underlying type recorded")

                if let underlyingType {
                    let kind = sema.types.kind(of: underlyingType)
                    if case .primitive(.int, .nonNull) = kind {
                        // Expected
                    } else {
                        Issue.record("Expected underlying type to be Int, got \(kind)")
                    }
                }
            }

            do {
                let userIdSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "UserId"
                }))
                #expect(userIdSymbol.flags.contains(.valueType), "@JvmInline value class should have valueType flag")

                let underlyingType = sema.symbols.valueClassUnderlyingType(for: userIdSymbol.id)
                #expect(underlyingType != nil, "@JvmInline value class should record an underlying type")
            }

            do {
                let legacySymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
                    symbol.kind == .class && interner.resolve(symbol.name) == "LegacyCount"
                }))
                #expect(legacySymbol.flags.contains(.valueType), "inline class should have valueType flag")
                #expect(!legacySymbol.flags.contains(.inlineFunction), "inline class should not be marked as inline function")

                let underlyingType = sema.symbols.valueClassUnderlyingType(for: legacySymbol.id)
                #expect(underlyingType != nil, "inline class should record an underlying type")
            }

            do {
                let badMultipleErrors = diagnosticsForPath(paths[3], in: ctx).filter { $0.severity == .error }
                #expect(
                    badMultipleErrors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
                    "Expected diagnostic about single constructor parameter for value class"
                )
            }

            do {
                let badSecondaryErrors = diagnosticsForPath(paths[4], in: ctx).filter { $0.severity == .error }
                #expect(
                    badSecondaryErrors.contains(where: { $0.message.contains("secondary constructors") }),
                    "Expected diagnostic about secondary constructors for value class"
                )
            }
        }
    }

    // MARK: - Lowering-level value class unboxing

    @Test
    func testValueClassUnboxingLowering() throws {
        let sources: [String] = [
            // Value class: constructor and property access
            """
            value class Meter(val amount: Int)

            fun getAmount(m: Meter): Int = m.amount
            fun create(): Int {
                val m = Meter(42)
                return m.amount
            }
            """,
            // Regular class: should still allocate
            """
            class Box(val value: Int)

            fun createBox(): Int {
                val b = Box(42)
                return b.value
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runToLowering(ctx)

            let module = try #require(ctx.kir)
            let interner = ctx.interner
            let kk_object_new = interner.intern("kk_object_new")
            let kk_array_get_inbounds = interner.intern("kk_array_get_inbounds")

            var hasValueClassAlloc = false
            var hasArrayGetOnValueClass = false
            var hasValueClassConstructorCall = false
            var hasObjectNew = false

            for function in findAllKIRFunctions(in: module) {
                for instruction in function.body {
                    switch instruction {
                    case let .call(symbol, _, _, _, _, _, _, _):
                        if let symbol,
                           let sym = ctx.sema?.symbols.symbol(symbol),
                           sym.kind == .constructor,
                           sym.flags.contains(.valueType) || {
                               guard let parentID = ctx.sema?.symbols.parentSymbol(for: symbol),
                                     let parentSym = ctx.sema?.symbols.symbol(parentID)
                               else { return false }
                               return parentSym.flags.contains(.valueType)
                           }()
                        {
                            hasValueClassConstructorCall = true
                        }
                    default:
                        break
                    }

                    if case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                       callee == kk_array_get_inbounds,
                       arguments.count == 2,
                       let receiverType = module.arena.exprType(arguments[0]),
                       case let .classType(classType) = ctx.sema?.types.kind(of: receiverType),
                       let sym = ctx.sema?.symbols.symbol(classType.classSymbol),
                       sym.flags.contains(.valueType)
                    {
                        hasArrayGetOnValueClass = true
                    }

                    if case let .call(_, callee, _, result, _, _, _, _) = instruction,
                       callee == kk_object_new
                    {
                        hasObjectNew = true
                        if let result,
                           let resultType = module.arena.exprType(result),
                           case let .classType(classType) = ctx.sema?.types.kind(of: resultType),
                           let sym = ctx.sema?.symbols.symbol(classType.classSymbol),
                           sym.flags.contains(.valueType)
                        {
                            hasValueClassAlloc = true
                        }
                    }
                }
            }

            #expect(
                !hasValueClassConstructorCall,
                "Value class constructor call should be rewritten by ValueClassUnboxingPass"
            )
            #expect(
                !hasArrayGetOnValueClass,
                "kk_array_get_inbounds on value class should be rewritten to copy"
            )
            #expect(
                !hasValueClassAlloc,
                "kk_object_new for value class should be eliminated by unboxing"
            )
            #expect(
                hasObjectNew,
                "Regular class should still use kk_object_new for allocation"
            )
        }
    }
}
#endif
