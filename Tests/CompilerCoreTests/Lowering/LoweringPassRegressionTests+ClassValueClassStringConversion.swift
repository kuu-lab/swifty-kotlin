#if canImport(Testing)
@testable import CompilerCore
import Testing

// A statically class-typed or value-class-typed value is represented at
// runtime as a heap pointer or (for a non-nullable value class) its raw
// unboxed underlying primitive. Neither representation carries enough
// information for the generic Any-fallback conversion (kk_any_to_string) to
// recover on its own -- it either prints "<object 0x...>" for the pointer
// case or the raw primitive as a plain number for the value-class case.
//
// String template interpolation, `+` concatenation, and `+=` compound
// assignment all funnel through CallLowerer.emitAnyToStringWithNullGuard (the
// same funnel BUG-204 taught to special-case enums); DataEnumSealedSynthesisPass's
// data class toString() synthesis renders each property with independent,
// duplicated tag logic that never went through that funnel. Both now resolve
// and call the value's own (user-defined or synthesized) toString() via the
// shared resolveClassOwnToStringCallee helper before falling back to the
// generic tag path.
extension LoweringPassRegressionTests {
    @Test
    func testDataClassInterpolationCallsOwnToString() throws {
        let source = """
        data class Box(val n: Int)
        fun render(b: Box): String {
            return "box=$b"
        }
        fun main() {
            println(render(Box(1)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ClassInterpolation", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let boxSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Box")]))
            let boxType = sema.types.make(.classType(ClassType(classSymbol: boxSymbol, args: [], nullability: .nonNull)))
            let ownToString = try #require(
                resolveClassOwnToStringCallee(for: boxType, sema: sema, interner: ctx.interner),
                "Box's synthesized toString() must be resolvable"
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)

            let callsOwnToString = body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == ownToString.symbol
            }
            #expect(callsOwnToString, "the interpolated data class must call its own toString(); body: \(body)")

            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(!callees.contains("kk_any_to_string"),
                    "a class-typed value must not reach the generic Any conversion; callees: \(callees)")
        }
    }

    @Test
    func testValueClassConcatenationCallsOwnToString() throws {
        let source = """
        @JvmInline
        value class Meters(val raw: Int) {
            override fun toString(): String = "${raw}m"
        }
        fun render(m: Meters): String {
            return "" + m
        }
        fun main() {
            println(render(Meters(5)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ValueClassConcat", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let metersSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Meters")]))
            let metersType = sema.types.make(.classType(ClassType(classSymbol: metersSymbol, args: [], nullability: .nonNull)))
            let ownToString = try #require(
                resolveClassOwnToStringCallee(for: metersType, sema: sema, interner: ctx.interner),
                "Meters's user-defined toString() must be resolvable"
            )

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)

            let callsOwnToString = body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == ownToString.symbol
            }
            #expect(callsOwnToString, "the concatenated value class must call its own toString(); body: \(body)")

            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(!callees.contains("kk_any_to_string"),
                    "a value class's raw primitive must not reach the generic Any conversion; callees: \(callees)")
        }
    }

    // A data class property that is itself class-typed or value-class-typed must
    // be rendered by the synthesized toString() via the property type's own
    // toString(), not the raw pointer/primitive tag path -- the field-rendering
    // counterpart to the two call-site tests above.
    @Test
    func testDataClassToStringSynthesisCallsFieldOwnToString() throws {
        let source = """
        @JvmInline
        value class Meters(val raw: Int) {
            override fun toString(): String = "${raw}m"
        }
        data class Distance(val amount: Meters)
        fun main() {
            println(Distance(Meters(5)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "DataClassFieldToString", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let metersSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Meters")]))
            let metersType = sema.types.make(.classType(ClassType(classSymbol: metersSymbol, args: [], nullability: .nonNull)))
            let ownToString = try #require(
                resolveClassOwnToStringCallee(for: metersType, sema: sema, interner: ctx.interner),
                "Meters's user-defined toString() must be resolvable"
            )
            let distanceSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Distance")]))
            let distanceToStringSymbol = try #require(
                sema.symbols.lookupAll(fqName: [ctx.interner.intern("Distance"), ctx.interner.intern("toString")]).first
            )
            _ = distanceSymbol

            let module = try #require(ctx.kir)
            let synthesizedToString = try #require(
                findAllKIRFunctions(in: module).first { $0.symbol == distanceToStringSymbol },
                "Distance's synthesized toString() KIR function must exist"
            )

            let callsFieldOwnToString = synthesizedToString.body.contains { instruction in
                guard case let .call(symbol, _, _, _, _, _, _, _) = instruction else { return false }
                return symbol == ownToString.symbol
            }
            #expect(callsFieldOwnToString,
                    "the synthesized toString() must render a value-class field via its own toString(); body: \(synthesizedToString.body)")

            let callees = extractCallees(from: synthesizedToString.body, interner: ctx.interner)
            #expect(!callees.contains("kk_any_to_string"),
                    "a value-class field must not be rendered via the generic Any conversion; callees: \(callees)")
        }
    }

    // A class receiver with no toString of its own (only the inherited
    // kotlin.Any.toString placeholder) has nothing to resolve to and must keep
    // using the generic conversion -- the rewrite is keyed on whether the class
    // actually has its own toString, not on the receiver being class-typed.
    @Test
    func testClassWithoutOwnToStringKeepsGenericAnyConversion() throws {
        let source = """
        class Holder(val code: Int)
        fun render(h: Holder): String {
            return "h=$h"
        }
        fun main() {
            println(render(Holder(1)))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], moduleName: "ClassNoOwnToString", emit: .kirDump)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            #expect(!ctx.diagnostics.hasError)

            let sema = try #require(ctx.sema)
            let holderSymbol = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Holder")]))
            let holderType = sema.types.make(.classType(ClassType(classSymbol: holderSymbol, args: [], nullability: .nonNull)))
            #expect(resolveClassOwnToStringCallee(for: holderType, sema: sema, interner: ctx.interner) == nil,
                    "Holder has no toString of its own, only the inherited kotlin.Any placeholder")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "render", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("kk_any_to_string"),
                    "a class with no toString of its own must keep the generic Any conversion; callees: \(callees)")
        }
    }
}
#endif
