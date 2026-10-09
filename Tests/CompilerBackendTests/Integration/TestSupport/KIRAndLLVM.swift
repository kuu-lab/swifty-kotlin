#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import RuntimeABI
import Testing

/// Like `extractCallees`, but also reports each call's argument count for
/// tests that need to distinguish overloads by arity.
func extractCalleesWithArgumentCounts(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [(String, Int)] {
    body.compactMap { instruction -> (String, Int)? in
        guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction else { return nil }
        return (interner.resolve(callee), arguments.count)
    }
}

/// Imported stdlib functions are mangled in a precompiled artifact, while
/// source-injected declarations retain their short Kotlin name in KIR.
func isKotlinCallee(_ actual: String, named expected: String) -> Bool {
    actual == expected || actual.hasPrefix("\(RuntimeABISpec.compilerGeneratedLinkNamePrefix)\(expected)_")
}

func containsKotlinCallee(_ expected: String, in callees: [String]) -> Bool {
    callees.contains { isKotlinCallee($0, named: expected) }
}

/// Select an ABI operation without pinning its public/private link-name prefix.
/// Missing or ambiguous operations fail the test instead of inventing a name.
func runtimeABIFunction(_ operation: String) throws -> RuntimeABIFunctionSpec {
    let matches = RuntimeABISpec.allFunctions.filter {
        runtimeABIOperation($0.name) == operation
    }
    try #require(matches.count == 1, "Expected one ABI declaration for \(operation), got \(matches)")
    return try #require(matches.first)
}

func runtimeABICallee(_ operation: String) throws -> String {
    try runtimeABIFunction(operation).name
}

func compilerInternalCallee(_ operation: String) throws -> String {
    let matches = RuntimeABISpec.compilerInternalNonThrowingCalleeNames.filter {
        runtimeABIOperation($0) == operation
    }
    try #require(matches.count == 1, "Expected one compiler intrinsic for \(operation), got \(matches)")
    return try #require(matches.first)
}

private func runtimeABIOperation(_ name: String) -> String {
    String(name.drop(while: { $0 == "_" }).split(separator: "_", maxSplits: 1).last ?? "")
}

/// Reject retired runtime targets even if Sema selected a source declaration.
func expectDeclaredRuntimeCalls(in body: [KIRInstruction], ctx: CompilationContext) throws {
    let module = try #require(ctx.kir)
    let generatedPrefix = RuntimeABISpec.compilerGeneratedLinkNamePrefix
    let runtimeNamespace = try #require(generatedPrefix.split(separator: "_").first)
    let declared = Set(RuntimeABIExterns.allExterns.map(\.name))
        .union(RuntimeABISpec.compilerInternalNonThrowingCalleeNames)
        .union(RuntimeABISpec.compilerInternalBuiltinCalleeNames)
        .union(findAllKIRFunctions(in: module).map { ctx.interner.resolve($0.name) })
    let unexpected = extractCallees(from: body, interner: ctx.interner).filter {
        $0.drop(while: { $0 == "_" }).split(separator: "_", maxSplits: 1).first == runtimeNamespace
            && !$0.hasPrefix(generatedPrefix) && !declared.contains($0)
    }
    #expect(unexpected.isEmpty, "Consumer KIR contains undeclared runtime calls: \(unexpected)")
}

/// Source routing remains observable in Sema even when artifact KIR is inlined.
func expectSourceBackedCall(_ name: String, in ctx: CompilationContext) throws {
    let sema = try #require(ctx.sema)
    let chosen = Set(sema.bindings.callBindings.values.map(\.chosenCallee)).filter {
        sema.symbols.symbol($0)?.name == ctx.interner.intern(name)
    }
    try #require(!chosen.isEmpty, "Expected a bound \(name) call")
    for symbol in chosen {
        #expect(sema.symbols.isSourceBackedSymbol(symbol), "\(name) must bind to Kotlin source")
        if let linkName = sema.symbols.externalLinkName(for: symbol) {
            #expect(RuntimeABISpec.byName[linkName] == nil, "\(name) must not bind directly to runtime ABI \(linkName)")
        }
    }
}

#endif
