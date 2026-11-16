extension JVMClasspathIndex {
    /// Read both generated adapters before treating a foreign class as a
    /// Kotlin value class. Their descriptors identify its physical carrier.
    func importedValueCarrier(for type: JVMValueType) -> JVMValueType? {
        guard let name = type.referenceName, let info = classes[name], info.isKotlinFileFacade == false,
              let unbox = info.methods.first(where: { $0.name == "unbox-impl" && !$0.isStatic && $0.parameters.isEmpty }),
              unbox.result != .unit,
              info.methods.contains(where: {
                  $0.name == "box-impl" && $0.isStatic && $0.descriptor == "(" + unbox.result.descriptor + ")L" + name + ";"
              }) else { return nil }
        return unbox.result
    }
}

extension JVMFunctionBuilder {
    func foreignResultType(_ physical: JVMValueType, resolved logical: JVMValueType) -> JVMValueType {
        if context.jvmImports?.importedValueCarrier(for: logical)?.descriptor == physical.descriptor {
            return physical
        }
        return logical
    }
}
