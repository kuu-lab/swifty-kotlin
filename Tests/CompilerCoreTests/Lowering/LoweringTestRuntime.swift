@testable import CompilerCore
import RuntimeABI
import Testing

/// Select ABI declarations by operation, leaving their public/internal link
/// spelling to the canonical extern view. Retired operations are checked via
/// `operation(of:)` so removing a declaration cannot make a negative test vacuous.
enum LoweringTestRuntime {
    private static let externsByOperation: [String: [RuntimeABIExterns.ExternDecl]] = {
        var result: [String: [RuntimeABIExterns.ExternDecl]] = [:]
        for declaration in RuntimeABIExterns.allExterns {
            guard let operation = operation(of: declaration.name) else { continue }
            result[operation, default: []].append(declaration)
        }
        return result
    }()

    static func name(_ operation: String) -> String {
        let matches = externsByOperation[operation] ?? []
        precondition(matches.count == 1, "Expected one ABI declaration for \(operation), got \(matches)")
        return matches[0].name
    }

    static func callee(_ operation: String, interner: StringInterner) -> InternedString {
        interner.intern(name(operation))
    }

    /// Compiler intrinsics have no external declaration or link-time target.
    static func intrinsic(_ operation: String) -> String {
        let matches = RuntimeABISpec.compilerInternalNonThrowingCalleeNames.filter {
            self.operation(of: $0) == operation
        }
        precondition(matches.count == 1, "Expected one compiler intrinsic for \(operation), got \(matches)")
        return matches.first!
    }

    static func operation(of name: String) -> String? {
        let spelling = name.hasPrefix("__") ? String(name.dropFirst(2)) : name
        guard let separator = spelling.firstIndex(of: "_"),
              spelling[..<separator] == "kk"
        else { return nil }
        return String(spelling[spelling.index(after: separator)...])
    }

    static func operations<S: Sequence>(in names: S) -> Set<String> where S.Element == String {
        Set(names.compactMap { operation(of: $0) })
    }

    /// Source-backed builders pass the start mode through one ABI entry point.
    /// Locate its argument by the contract instead of pinning a launcher family
    /// or a positional index left over from the synthetic overloads.
    static func coroutineStartModes(
        for operation: String,
        legacyOperationPrefix: String,
        allowedLegacyOperations: Set<String> = [],
        in module: KIRModule,
        interner: StringInterner
    ) throws -> [Int64] {
        let linkName = name(operation)
        let spec = try #require(RuntimeABISpec.allFunctions.first { $0.name == linkName })
        let startIndex = try #require(spec.parameters.firstIndex { $0.name == "start" })
        let callee = interner.intern(linkName)
        let functions = findAllKIRFunctions(in: module)
        let legacyOperations = operations(in: functions.flatMap {
            extractCallees(from: $0.body, interner: interner)
        }).filter {
            $0.hasPrefix(legacyOperationPrefix) && !allowedLegacyOperations.contains($0)
        }
        #expect(legacyOperations.isEmpty, "Source-backed builder must not also emit legacy launchers: \(legacyOperations)")
        let calls = functions.flatMap { function in
            function.body.compactMap { instruction -> [KIRExprID]? in
                guard case let .call(_, target, arguments, _, _, _, _, _) = instruction,
                      target == callee else { return nil }
                return arguments
            }
        }
        return try calls.map { arguments in
            #expect(arguments.count == spec.parameters.count)
            try #require(arguments.indices.contains(startIndex))
            let ordinal = module.arena.expr(arguments[startIndex]).flatMap { expression -> Int64? in
                guard case let .intLiteral(value) = expression else { return nil }
                return value
            }
            return try #require(ordinal, "Builder start mode must lower to its integer ordinal")
        }
    }

    /// The blocking wrapper passes the state-machine symbol to the canonical
    /// continuation factory; follow that identity instead of its generated name.
    static func loweredSuspendFunction(
        for wrapper: KIRFunction,
        in module: KIRModule,
        interner: StringInterner
    ) throws -> KIRFunction {
        let factory = callee("coroutine_continuation_new", interner: interner)
        let targets = wrapper.body.compactMap { instruction -> SymbolID? in
            guard case let .call(_, callee, arguments, _, _, _, _, _) = instruction,
                  callee == factory, let argument = arguments.first,
                  case let .intLiteral(rawValue)? = module.arena.expr(argument)
            else { return nil }
            return SymbolID(rawValue: Int32(rawValue))
        }
        let target = try #require(targets.first, "Suspend wrapper must identify its state machine")
        #expect(targets.count == 1)
        return try #require(findAllKIRFunctions(in: module).first { $0.symbol == target })
    }
}
