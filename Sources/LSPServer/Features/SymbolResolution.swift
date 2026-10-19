import CompilerCore

enum SymbolResolution {
    static func symbol(for expr: ExprID, sema: SemaModule) -> SymbolID? {
        if let symbol = sema.bindings.identifierSymbol(for: expr) {
            return symbol
        }
        if let call = sema.bindings.callBinding(for: expr) {
            return call.chosenCallee
        }
        if let target = sema.bindings.callableTarget(for: expr) {
            switch target {
            case let .symbol(symbol), let .localValue(symbol):
                return symbol
            }
        }
        if let valueCall = sema.bindings.callableValueCallBinding(for: expr),
           let target = valueCall.target
        {
            switch target {
            case let .symbol(symbol), let .localValue(symbol):
                return symbol
            }
        }
        return nil
    }

    static func label(for kind: SymbolKind) -> String {
        switch kind {
        case .package: "package"
        case .class: "class"
        case .interface: "interface"
        case .object: "object"
        case .enumClass: "enum class"
        case .annotationClass: "annotation class"
        case .typeAlias: "typealias"
        case .function: "function"
        case .constructor: "constructor"
        case .property: "property"
        case .field: "field"
        case .backingField: "backing field"
        case .typeParameter: "type parameter"
        case .valueParameter: "parameter"
        case .local: "local"
        case .label: "label"
        }
    }
}
