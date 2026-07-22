@testable import CompilerCore
@testable import CompilerBackend
import XCTest

func findAllKIRFunctions(in module: KIRModule) -> [KIRFunction] {
    module.arena.declarations.compactMap { decl -> KIRFunction? in
        guard case let .function(function) = decl else { return nil }
        return function
    }
}

func findKIRFunction(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> KIRFunction {
    let function = findAllKIRFunctions(in: module).first { function in
        interner.resolve(function.name) == name
    }
    return try XCTUnwrap(function, "KIR function '\(name)' not found in module", file: file, line: line)
}

func findKIRFunctionBody(
    named name: String,
    in module: KIRModule,
    interner: StringInterner,
    file: StaticString = #filePath,
    line: UInt = #line
) throws -> [KIRInstruction] {
    let function = try findKIRFunction(named: name, in: module, interner: interner, file: file, line: line)
    return function.body
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
