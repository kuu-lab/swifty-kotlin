#if canImport(Testing)
@testable import CompilerCore
import RuntimeABI
import Testing

/// Select a semantic operation from the canonical ABI, retaining its exported
/// name, parameter types, and throwing contract. Missing or ambiguous entries
/// fail the test instead of falling back to a reconstructed runtime name.
func loweringRuntimeABI(_ operation: String) throws -> RuntimeABIFunctionSpec {
    let matches = RuntimeABISpec.allFunctions.filter {
        $0.name.split(separator: "_").dropFirst().joined(separator: "_") == operation
    }
    try #require(matches.count == 1, "Expected one runtime ABI entry for \(operation), got: \(matches)")
    return try #require(matches.first)
}

/// LLVM intrinsics have canonical compiler-internal names but no C extern
/// declaration. Look up both catalogs without inventing a runtime ABI for them.
func loweringCompilerCallee(_ operation: String, interner: StringInterner) throws -> InternedString {
    let names = Set(RuntimeABISpec.allFunctions.map(\.name))
        .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames)
    let matches = names.filter {
        $0.split(separator: "_").dropFirst().joined(separator: "_") == operation
    }
    try #require(matches.count == 1, "Expected one compiler callee for \(operation), got: \(matches)")
    return interner.intern(try #require(matches.first))
}

enum LoweringBoxingDirection: String {
    case box
    case unbox
}

/// Independent expectations for the compiler's primitive routing table. The
/// small integer unbox sharing and null-sentinel overrides remain explicit;
/// the exported names themselves come from RuntimeABISpec.
func loweringBoxingABI(
    _ direction: LoweringBoxingDirection,
    for primitive: PrimitiveType,
    nonNull: Bool = false,
    staticPrimitive: Bool = false
) throws -> RuntimeABIFunctionSpec {
    let representation: String = switch (direction, primitive) {
    case (.unbox, .byte), (.unbox, .short), (.unbox, .uint), (.unbox, .ubyte), (.unbox, .ushort): "int"
    case (_, .boolean): "bool"
    default: primitive.rawValue
    }
    var operation = [direction.rawValue, representation]
    if nonNull && (primitive == .double || (direction == .box && (primitive == .long || primitive == .ulong))) {
        operation.append("nonnull")
    }
    if staticPrimitive {
        operation.append("static")
    }
    return try loweringRuntimeABI(operation.joined(separator: "_"))
}

struct LoweringTestCall {
    let symbol: SymbolID?
    let callee: InternedString
    let arguments: [KIRExprID]
    let result: KIRExprID?
    let canThrow: Bool
    let thrownResult: KIRExprID?

    init?(_ instruction: KIRInstruction) {
        guard case let .call(symbol, callee, arguments, result, canThrow, thrownResult, _, _) = instruction else {
            return nil
        }
        self.symbol = symbol
        self.callee = callee
        self.arguments = arguments
        self.result = result
        self.canThrow = canThrow
        self.thrownResult = thrownResult
    }
}

func loweringCalls(in body: [KIRInstruction]) -> [LoweringTestCall] {
    body.compactMap(LoweringTestCall.init)
}

/// Require runtime calls and check their ABI shape. KIR keeps outThrown
/// separate from ordinary arguments, so exclude that C parameter.
func requireLoweringRuntimeCalls(
    _ abi: RuntimeABIFunctionSpec,
    in body: [KIRInstruction],
    interner: StringInterner
) throws -> [LoweringTestCall] {
    let callee = interner.intern(abi.name)
    let calls = loweringCalls(in: body).filter { $0.callee == callee }
    try #require(!calls.isEmpty, "Expected a call to \(abi.name)")
    for call in calls {
        #expect(call.arguments.count == abi.parameters.filter { $0.name != "outThrown" }.count)
        #expect(call.canThrow == abi.isThrowing)
        if !abi.isThrowing {
            #expect(call.thrownResult == nil)
        }
    }
    return calls
}

func requireLoweringRuntimeCall(
    _ abi: RuntimeABIFunctionSpec,
    in body: [KIRInstruction],
    interner: StringInterner
) throws -> LoweringTestCall {
    let calls = try requireLoweringRuntimeCalls(abi, in: body, interner: interner)
    try #require(calls.count == 1, "Expected one call to \(abi.name), got: \(calls)")
    return try #require(calls.first)
}
#endif
