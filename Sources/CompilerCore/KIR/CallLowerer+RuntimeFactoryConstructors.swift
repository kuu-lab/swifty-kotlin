import RuntimeABI

extension CallLowerer {
    /// True when the constructor's runtime ABI entry point is a factory that
    /// allocates and returns an object handle (e.g. built-in exception
    /// `kk_*_exception_new_message`). Such constructors must not receive an
    /// implicit `this` allocated by `kk_object_new`.
    func isRuntimeFactoryConstructor(
        _ symbolID: SymbolID,
        sema: SemaModule
    ) -> Bool {
        guard let externalLinkName = sema.symbols.externalLinkName(for: symbolID),
              !externalLinkName.isEmpty,
              let signature = sema.symbols.functionSignature(for: symbolID),
              let spec = RuntimeABISpec.byName[externalLinkName]
        else {
            return false
        }
        let abiValueParameters = spec.parameters.filter { parameter in
            !(spec.isThrowing && parameter.name == "outThrown" && parameter.type == .nullableIntptrPointer)
        }
        // Coroutine rewrite adds functionID / launcherArgCount after CallLowerer
        // expands the suspend block to (fnPtr, closureRaw), so the Kotlin
        // constructor signature no longer matches the ABI parameter list.
        if !abiParametersMatchFactorySignature(abiValueParameters, signature, sema: sema),
           externalLinkName != "__kk_deep_recursive_function_new"
        {
            return false
        }
        switch spec.returnType {
        case .intptr, .opaquePointer, .nullableOpaquePointer:
            return true
        default:
            return false
        }
    }

    /// Checks whether the runtime ABI parameters (with the trailing `outThrown`
    /// slot removed) line up with the Kotlin-level constructor signature.
    /// A `String` parameter may be lowered as a single pointer/handle or as a
    /// flat 4-word aggregate (`data`, `length`, `byteCount`, `hash`) depending on
    /// the ABI entry point; the backend has its own tables for the latter, so
    /// this helper recognises the flat-string pattern so `String` factory
    /// constructors are not mistaken for normal `this`-accepting constructors.
    private func abiParametersMatchFactorySignature(
        _ abiParameters: [RuntimeABIParameter],
        _ signature: FunctionSignature,
        sema: SemaModule
    ) -> Bool {
        var abiIndex = 0
        for parameterType in signature.parameterTypes {
            guard abiIndex < abiParameters.count else { return false }
            // Function-valued constructor parameters are expanded to a raw
            // function pointer and closure handle before reaching a runtime
            // factory bridge (for example DeepRecursiveFunction's block).
            if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                guard abiIndex + 1 < abiParameters.count,
                      abiParameters[abiIndex].type == .intptr,
                      abiParameters[abiIndex + 1].type == .intptr
                else {
                    return false
                }
                abiIndex += 2
                continue
            }
            if isFlatStringGroup(at: abiIndex, in: abiParameters) {
                abiIndex += 4
            } else {
                abiIndex += 1
            }
        }
        return abiIndex == abiParameters.count
    }

    func runtimeExternalOmitsObjectReceiver(_ symbolID: SymbolID, sema: SemaModule) -> Bool {
        guard let owner = sema.symbols.parentSymbol(for: symbolID),
              sema.symbols.symbol(owner)?.kind == .object,
              let signature = sema.symbols.functionSignature(for: symbolID),
              let linkName = sema.symbols.externalLinkName(for: symbolID),
              let spec = RuntimeABISpec.byName[linkName]
        else {
            return false
        }
        let valueParameters = spec.parameters.filter {
            !($0.name == "outThrown" && $0.type == .nullableIntptrPointer)
        }
        return abiParametersMatchFactorySignature(valueParameters, signature, sema: sema)
    }

    private func isFlatStringGroup(
        at index: Int,
        in parameters: [RuntimeABIParameter]
    ) -> Bool {
        guard index + 3 < parameters.count else { return false }
        let dataParam = parameters[index]
        let lengthParam = parameters[index + 1]
        let byteCountParam = parameters[index + 2]
        let hashParam = parameters[index + 3]
        guard dataParam.type == .nullableConstUInt8Pointer,
              lengthParam.type == .intptr,
              byteCountParam.type == .intptr,
              hashParam.type == .intptr
        else {
            return false
        }
        // Unprefixed flat-string quartet used by many single-string entry points.
        if dataParam.name == "data"
            && lengthParam.name == "length"
            && byteCountParam.name == "byteCount"
            && hashParam.name == "hash"
        {
            return true
        }
        guard dataParam.name.hasSuffix("Data") else { return false }
        let prefix = String(dataParam.name.dropLast(4))
        return lengthParam.name == "\(prefix)Length"
            && byteCountParam.name == "\(prefix)ByteCount"
            && hashParam.name == "\(prefix)Hash"
    }
}
