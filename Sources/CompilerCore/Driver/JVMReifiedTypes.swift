import Foundation

extension JVMProgramBuilder {
    func specialized(_ id: TypeID, visiting: Set<SymbolID> = []) -> TypeID {
        guard !inlineTypeArguments.isEmpty else { return id }
        switch sema.types.kind(of: id) {
        case let .typeParam(t):
            guard !visiting.contains(t.symbol), let replacement = inlineTypeArguments[t.symbol], replacement != id else { return id }
            let actual = specialized(replacement, visiting: visiting.union([t.symbol]))
            return t.nullability == .nullable ? sema.types.makeNullable(actual) : actual
        case let .intersection(parts): return sema.types.make(.intersection(parts.map { specialized($0, visiting: visiting) }))
        case let .classType(t):
            return sema.types.make(.classType(ClassType(classSymbol: t.classSymbol, args: t.args.map { arg in arg.mapTypes { specialized($0, visiting: visiting) } }, nullability: t.nullability)))
        case let .functionType(f):
            return sema.types.make(.functionType(FunctionType(contextReceivers: f.contextReceivers.map { specialized($0, visiting: visiting) }, receiver: f.receiver.map { specialized($0, visiting: visiting) }, params: f.params.map { specialized($0, visiting: visiting) }, returnType: specialized(f.returnType, visiting: visiting), isSuspend: f.isSuspend, isCallableReference: f.isCallableReference, nullability: f.nullability, throws: f.throws.map { specialized($0, visiting: visiting) })))
        default: return id
        }
    }
    func validReifiedArgument(_ id: TypeID) -> Bool {
        let actual = specialized(id)
        switch sema.types.kind(of: actual) {
        case .typeParam: return isReifiedParameter(actual)
        case let .classType(t) where (try? className(t.classSymbol)) == "kotlin/Array":
            guard let arg = t.args.first else { return false }
            switch arg { case let .invariant(t), let .out(t): return validReifiedArgument(t); case .in, .star: return true }
        default: return true
        }
    }
    func isReifiedParameter(_ id: TypeID) -> Bool {
        if case let .typeParam(t) = sema.types.kind(of: id) { return sema.symbols.symbol(t.symbol)?.flags.contains(.reifiedTypeParameter) == true }
        return false
    }
    func reifiedUse(_ id: TypeID) -> String? {
        let actual = specialized(id)
        func name(_ type: TypeID) -> String? {
            switch sema.types.kind(of: type) {
            case let .typeParam(t) where isReifiedParameter(type): return context.interner.resolve(sema.symbols.symbol(t.symbol)!.name)
            case let .classType(t) where (try? className(t.classSymbol)) == "kotlin/Array":
                guard let arg = t.args.first else { return nil }
                switch arg { case let .invariant(element), let .out(element): return name(element).map { "[" + $0 }; default: return nil }
            default: return nil
            }
        }
        return name(actual).map { $0 + (sema.types.nullability(of: actual) == .nullable ? "?" : "") }
    }
}
