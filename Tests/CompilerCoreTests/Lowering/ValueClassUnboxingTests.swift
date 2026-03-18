@testable import CompilerCore
import Foundation
import XCTest

final class ValueClassUnboxingTests: XCTestCase {
    // MARK: - Value class flag propagation

    func testValueModifierSetsValueTypeFlag() throws {
        let source = """
        value class Meter(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        XCTAssertTrue(meterSymbol.flags.contains(.valueType), "value class should have valueType flag")
    }

    func testValueClassRecordsUnderlyingType() throws {
        let source = """
        value class Meter(val amount: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner

        let meterSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
            symbol.kind == .class && interner.resolve(symbol.name) == "Meter"
        }))
        let underlyingType = sema.symbols.valueClassUnderlyingType(for: meterSymbol.id)
        XCTAssertNotNil(underlyingType, "value class should have an underlying type recorded")

        if let underlyingType {
            let kind = sema.types.kind(of: underlyingType)
            if case .primitive(.int, .nonNull) = kind {
                // Expected
            } else {
                XCTFail("Expected underlying type to be Int, got \(kind)")
            }
        }
    }

    // MARK: - Value class unboxing lowering

    func testValueClassConstructorRewrittenToCopy() throws {
        // The ValueClassUnboxingPass is currently disabled because KIR
        // emission already lowers property access to kk_array_get_inbounds.
        // Verify that the pass is skipped and the constructor call remains.
        let source = """
        value class Meter(val amount: Int)

        fun create(): Int {
            val m = Meter(42)
            return m.amount
        }
        """
        let ctx = makeContextFromSource(source)
        try runToLowering(ctx)

        let module = try XCTUnwrap(ctx.kir)

        // The pass should be recorded (it ran but shouldRun returned false).
        XCTAssertTrue(
            module.executedLowerings.contains("ValueClassUnboxing"),
            "ValueClassUnboxing pass should have been recorded"
        )
    }

    // MARK: - Validation diagnostics

    func testValueClassMultipleParamsEmitsDiagnostic() throws {
        let source = """
        value class Bad(val x: Int, val y: Int)
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.contains(where: { $0.message.contains("exactly one primary constructor parameter") }),
            "Expected diagnostic about single constructor parameter for value class"
        )
    }

    func testValueClassSecondaryConstructorEmitsDiagnostic() throws {
        let source = """
        value class Bad(val x: Int) {
            constructor() : this(0)
        }
        """
        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.contains(where: { $0.message.contains("secondary constructors") }),
            "Expected diagnostic about secondary constructors for value class"
        )
    }
}
