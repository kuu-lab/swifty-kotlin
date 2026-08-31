#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

func findAllKIRFunctions(in module: KIRModule) -> [KIRFunction] {
    CompilerTestSupport.findAllKIRFunctions(in: module)
}

func findKIRFunction(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> KIRFunction {
    try CompilerTestSupport.findKIRFunction(named: name, in: module, interner: interner, file: file, line: line)
}

func findKIRFunctionBody(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [KIRInstruction] {
    try CompilerTestSupport.findKIRFunctionBody(named: name, in: module, interner: interner, file: file, line: line)
}

func extractCallees(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String] {
    CompilerTestSupport.extractCallees(from: body, interner: interner)
}

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
    actual == expected || actual.hasPrefix("kk_fn_\(expected)_")
}

func containsKotlinCallee(_ expected: String, in callees: [String]) -> Bool {
    callees.contains { isKotlinCallee($0, named: expected) }
}

func extractThrowFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String: [Bool]] {
    CompilerTestSupport.extractThrowFlags(from: body, interner: interner)
}
#endif
