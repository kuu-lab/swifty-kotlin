private let abi = RuntimeABISectionBuilder("Reflection")

public extension RuntimeABISpec {
    static let kParameterFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_kparameter_set_array_component", "parameterRaw component"),
        // KUU-1364: the 4th argument is a RuntimeKParameterFlags bitmask
        // (bit0 = isOptional, bit1 = isVararg) — the signature is unchanged
        // so older artifacts keep passing 0/1 and simply lack the vararg bit.
        abi.nt("__kk_kparameter_create_typed", "index nameRaw typeRaw flags kind typeToken callableOwner"),
        abi.nt("__kk_kparameter_create", "index nameRaw typeRaw flags kind"),
        abi.nt("__kk_kparameter_get_index", "handle"),
        abi.nt("__kk_kparameter_get_name", "handle"),
        abi.nt("__kk_kparameter_get_type", "handle"),
        abi.nt("__kk_kparameter_is_optional", "handle"),
        abi.nt("__kk_kparameter_get_kind", "handle"),
        abi.nt("__kk_kparameter_is_vararg", "handle"),
    ]

    static let kFunctionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_register_annotation_factory",
            parameters: ["callableRaw", "fqNameRaw", "argsEncodedRaw", "argCount", "factory"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            }, returnType: .intptr, section: "Reflection", isThrowing: false
        ),
        abi.th("__kk_kcallable_get_annotations_typed", "callableRaw outThrown"),
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_register_single_annotation",
            parameters: ["callableRaw", "fqNameRaw", "argsEncodedRaw", "argCount"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            }, returnType: .intptr, section: "Reflection", isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_register",
            parameters: ["raw", "invoker", "environment", "parameters", "typeParameters", "flags", "visibility", "setterInvoker", "setterParameters"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            }, returnType: .intptr, section: "Reflection", isThrowing: false
        ),
        abi.nt("__kk_kcallable_register_return_type", "raw returnTypeKTypeRaw"),
        abi.nt("__kk_kcallable_is_runtime", "raw"),
        abi.nt("__kk_kcallable_get_metadata", "raw member"),
        abi.th("__kk_kcallable_call", "raw arguments outThrown"),
        abi.th("__kk_kcallable_call_by", "raw arguments outThrown"),
        abi.th("__kk_java_class_get_constructor", "classRaw parameterTypesRaw outThrown"),
        abi.th("__kk_java_constructor_new_instance", "constructorRaw argumentsRaw outThrown"),
        abi.nt("__kk_kfunction_create", "nameRaw arity returnTypeRaw flags fnPtr closureRaw"),
        abi.nt("__kk_kfunction_create_full", "nameRaw arity returnTypeRaw flags fnPtr closureRaw paramListRaw typeStringRaw"),
        abi.nt("__kk_kcallable_get_name", "handle"),
        abi.nt("__kk_kcallable_get_return_type", "handle"),
        abi.nt("__kk_kfunction_is_suspend", "handle"),
        // KUU-1357: KFunction modifier flags packed in the create/tag `flags`
        // argument (bit1=inline, bit2=operator, bit3=infix, bit4=external).
        abi.nt("__kk_kfunction_is_inline", "handle"),
        abi.nt("__kk_kfunction_is_operator", "handle"),
        abi.nt("__kk_kfunction_is_infix", "handle"),
        abi.nt("__kk_kfunction_is_external", "handle"),
        abi.nt("__kk_kfunction_get_parameters", "handle"),
        abi.nt("__kk_kfunction_get_value_parameters", "handle"),
        abi.nt("__kk_kfunction_get_type", "handle"),
        abi.th("__kk_kfunction_call_0", "handle outThrown"),
        abi.th("__kk_kfunction_call_1", "handle arg outThrown"),
        abi.th("__kk_kfunction_call_2", "handle arg1 arg2 outThrown"),
        abi.th("__kk_kfunction_call_3", "handle arg1 arg2 arg3 outThrown"),
        abi.th("__kk_kfunction_call_vararg", "handle argsListRaw outThrown"),
        abi.th("__kk_kconstructor_create", "nameRaw arity returnTypeRaw fnPtr isPrimary visibilityRaw declaringClassRaw"),
        abi.nt("__kk_kconstructor_set_parameter_type", "constructorRaw index typeToken"),
        abi.nt("__kk_kconstructor_set_jvm_visibility", "constructorRaw visibilityOrdinal"),
    ]

    static let callableRefFunctions: [RuntimeABIFunctionSpec] = [
        abi.nt("__kk_function_copy_description", "source target", ret: .void),
        abi.nt("__kk_function_set_description", "value descriptionRaw identity", ret: .void),
        abi.nt("kk_callable_ref_tag_kfunction", "callable name returnType arity flags"),
        abi.nt("__kk_callable_ref_set_identity", "callable targetRaw capturesRaw", ret: .void),
        abi.nt("__kk_function_value_set_callable_ref_identity", "callable targetRaw capturesRaw arity kind flags", ret: .void),
        abi.nt("__kk_reflection_member_set_identity", "member targetRaw returnTypeRaw arity kind flags", ret: .void),
        abi.nt("__kk_callable_adapter_set_identity", "callable samInterfaceTypeID targetRaw capturesRaw arity flags returnTypeRaw", ret: .void),
        abi.nt("__kk_sam_adapter_set_identity", "callable interfaceTypeID targetRaw capturesRaw arity flags", ret: .void),
        abi.nt("kk_callable_ref_tag_kproperty", "callable name returnType arity"),
    ]
}
