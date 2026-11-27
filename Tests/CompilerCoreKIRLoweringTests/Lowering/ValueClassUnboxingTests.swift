#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct ValueClassUnboxingTests {

    @Test
    func testValueModifierSetsValueTypeFlag() throws {
        let source = """
        value class Meter(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && symbol.name == interner.intern("Meter")
        }))
        #expect(meterSymbol.flags.contains(.valueType), "value class should have valueType flag")
    }

    @Test
    func testValueClassRecordsUnderlyingType() throws {
        let source = """
        value class Meter(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && symbol.name == interner.intern("Meter")
        }))
        let underlyingType = sema.symbols.valueClassUnderlyingType(for: meterSymbol.id)
        #expect(underlyingType != nil, "value class should have an underlying type recorded")

        if let underlyingType {
            let kind = sema.types.kind(of: underlyingType)
            if case .primitive(.int, .nonNull) = kind {
            } else {
                Issue.record("Expected underlying type to be Int, got \(kind)")
            }
        }
    }

    @Test
    func testJvmInlineValueClassSetsValueTypeFlag() throws {
        let source = """
        @JvmInline
        value class UserId(val raw: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let userIdSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && symbol.name == interner.intern("UserId")
        }))
        #expect(userIdSymbol.flags.contains(.valueType), "@JvmInline value class should have valueType flag")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: userIdSymbol.id)
        #expect(underlyingType != nil, "@JvmInline value class should record an underlying type")
    }

    @Test
    func testInlineClassSetsValueTypeFlag() throws {
        let source = """
        inline class LegacyCount(val raw: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let legacyCountSymbol = try #require(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && symbol.name == interner.intern("LegacyCount")
        }))
        #expect(legacyCountSymbol.flags.contains(.valueType), "inline class should have valueType flag")
        #expect(!legacyCountSymbol.flags.contains(.inlineFunction), "inline class should not be marked as inline function")

        let underlyingType = sema.symbols.valueClassUnderlyingType(for: legacyCountSymbol.id)
        #expect(underlyingType != nil, "inline class should record an underlying type")
    }

    @Test
    func testValueClassConstructorRewrittenToCopy() throws {
        let source = """
        value class Meter(val amount: Int)

        fun create(): Int {
            val m = Meter(42)
            return m.amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)

        #expect(
            module.executedLowerings.contains("ValueClassUnboxing"),
            "ValueClassUnboxing pass should have been recorded"
        )

        var hasValueClassConstructorCall = false
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
            }
        }

        #expect(
            !hasValueClassConstructorCall,
            "Value class constructor call should be rewritten by ValueClassUnboxingPass"
        )
    }

    @Test
    func testValueClassPropertyAccessRewrittenToCopy() throws {
        let source = """
        value class Meter(val amount: Int)

        fun getAmount(m: Meter): Int = m.amount
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let interner = ctx.interner
        let kk_array_get_inbounds = LoweringTestRuntime.callee("array_get_inbounds", interner: interner)

        var hasArrayGetOnValueClass = false
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                if case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                   callee == kk_array_get_inbounds,
                   arguments.count == 2
                {
                    if let receiverType = module.arena.exprType(arguments[0]),
                       case let .classType(classType) = ctx.sema?.types.kind(of: receiverType),
                       let sym = ctx.sema?.symbols.symbol(classType.classSymbol),
                       sym.flags.contains(.valueType)
                    {
                        hasArrayGetOnValueClass = true
                    }
                }
            }
        }

        #expect(
            !hasArrayGetOnValueClass,
            "The inbounds array read on a value class should be rewritten to copy"
        )
    }

    @Test
    func testValueClassNoHeapAllocation() throws {
        let source = """
        value class Meter(val amount: Int)

        fun create(): Int {
            val m = Meter(42)
            return m.amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let interner = ctx.interner
        let kk_object_new = LoweringTestRuntime.callee("object_new", interner: interner)

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

        #expect(
            !hasValueClassAlloc,
            "The object allocation for a value class should be eliminated by unboxing"
        )
    }

    @Test
    func testNonValueClassNotAffected() throws {
        let source = """
        class Box(val value: Int)

        fun create(): Int {
            val b = Box(42)
            return b.value
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try #require(ctx.kir)
        let interner = ctx.interner
        let kk_object_new = LoweringTestRuntime.callee("object_new", interner: interner)

        var hasObjectNew = false
        for function in findAllKIRFunctions(in: module) {
            for instruction in function.body {
                if case let .call(_, callee, _, _, _, _, _, _) = instruction,
                   callee == kk_object_new
                {
                    hasObjectNew = true
                }
            }
        }

        #expect(
            hasObjectNew,
            "Regular class should still use kk_object_new for allocation"
        )
    }

    @Test
    func testValueClassMultipleParamsEmitsDiagnostic() throws {
        let source = """
        value class Bad(val x: Int, val y: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(
            errors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
            "Expected diagnostic about single constructor parameter for value class"
        )
    }

    @Test
    func testValueClassSecondaryConstructorLowersOnNative() throws {
        let source = """
        @JvmInline value class Value(val x: Int) {
            constructor(s: String) : this(s.length)
        }

        fun main() {
            Value("abc").x
        }
        """
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [path],
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        try runToLowering(ctx)

        #expect(
            !ctx.diagnostics.diagnostics.contains(where: { $0.code == "KSWIFTK-SEMA-0071" }),
            "A legal value-class secondary constructor should be accepted on native"
        )
        #expect(
            !ctx.diagnostics.diagnostics.contains(where: { $0.severity == .error && $0.message.contains("KIR verifier") }),
            "A legal value-class secondary constructor should produce valid KIR"
        )
    }
}
#endif
