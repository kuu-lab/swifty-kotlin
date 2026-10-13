#if canImport(Testing)
@testable import CompilerCore
import Testing

func findAllKIRFunctions(in module: KIRModule) -> [KIRFunction] {
    module.arena.declarations.compactMap { decl -> KIRFunction? in
        guard case let .function(function) = decl else { return nil }
        return function
    }
}

private struct MissingKIRFunctionError: Error {
    let name: String
}

func findKIRFunction(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> KIRFunction {
    guard let function = findAllKIRFunctions(in: module).first(where: { function in
        interner.resolve(function.name) == name
    }) else {
        // 非テストターゲットでは TestingMacros が使えないため #require の代わりに
        // Issue.record + throw でテスト失敗とする。
        Issue.record(
            "KIR function '\(name)' not found in module",
            sourceLocation: sourceLocation
        )
        throw MissingKIRFunctionError(name: name)
    }
    return function
}

func findKIRFunctionBody(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    sourceLocation: Testing.SourceLocation = #_sourceLocation
) throws -> [KIRInstruction] {
    try findKIRFunction(
        named: name, in: module, interner: interner, sourceLocation: sourceLocation
    ).body
}

func extractCallees(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String] {
    body.compactMap { instruction -> String? in
        guard case let .call(_, callee, _, _, _, _, _, _) = instruction else { return nil }
        return interner.resolve(callee)
    }
}

func extractThrowFlags(
    from body: [KIRInstruction],
    interner: StringInterner
) -> [String: [Bool]] {
    body.reduce(into: [:]) { partial, instruction in
        guard case let .call(_, callee, _, _, canThrow, _, _, _) = instruction else { return }
        partial[interner.resolve(callee), default: []].append(canThrow)
    }
}
#endif
