// KFunction / KProperty / KConstructor / KParameter / CallableRef ABI specs
// (STDLIB-REFLECT-063 / STDLIB-REFLECT-067 / REFL-003)

public extension RuntimeABISpec {
    /// KParameter reflection runtime functions (STDLIB-REFLECT-063).
    static let kParameterFunctions: [RuntimeABIFunctionSpec] = [
        // KUU-1364: the 4th argument is a RuntimeKParameterFlags bitmask
        // (bit0 = isOptional, bit1 = isVararg) — the signature is unchanged
        // so older artifacts keep passing 0/1 and simply lack the vararg bit.
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_create_typed",
            parameters: [
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
                RuntimeABIParameter(name: "kind", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "callableOwner", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_create",
            parameters: [
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
                RuntimeABIParameter(name: "kind", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_get_index",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_get_name",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_get_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_is_optional",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_get_kind",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kparameter_is_vararg",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
    ]

    /// KFunction, KProperty, and KConstructor reflection runtime functions.
    static let kFunctionFunctions: [RuntimeABIFunctionSpec] = [
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
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_is_runtime",
            parameters: [RuntimeABIParameter(name: "raw", type: .intptr)],
            returnType: .intptr, section: "Reflection", isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_get_metadata",
            parameters: [RuntimeABIParameter(name: "raw", type: .intptr), RuntimeABIParameter(name: "member", type: .intptr)],
            returnType: .intptr, section: "Reflection", isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_call",
            parameters: [RuntimeABIParameter(name: "raw", type: .intptr), RuntimeABIParameter(name: "arguments", type: .intptr),
                         RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)],
            returnType: .intptr, section: "Reflection", isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_call_by",
            parameters: [RuntimeABIParameter(name: "raw", type: .intptr), RuntimeABIParameter(name: "arguments", type: .intptr),
                         RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)],
            returnType: .intptr, section: "Reflection", isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_create",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "returnTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_create_full",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "returnTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "paramListRaw", type: .intptr),
                RuntimeABIParameter(name: "typeStringRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_get_name",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kcallable_get_return_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_is_suspend",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        // KUU-1357: KFunction modifier flags packed in the create/tag `flags`
        // argument (bit1=inline, bit2=operator, bit3=infix, bit4=external).
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_is_inline",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_is_operator",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_is_infix",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_is_external",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_get_parameters",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_get_value_parameters",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_get_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_call_0",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_call_1",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_call_2",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_call_3",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "arg3", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kfunction_call_vararg",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "argsListRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kconstructor_create",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "returnTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "isPrimary", type: .intptr),
                RuntimeABIParameter(name: "visibilityRaw", type: .intptr),
                RuntimeABIParameter(name: "declaringClassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
    ]

    /// Callable reference type identity functions (REFL-003).
    static let callableRefFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_function_copy_description",
            parameters: [
                RuntimeABIParameter(name: "source", type: .intptr),
                RuntimeABIParameter(name: "target", type: .intptr),
            ],
            returnType: .void,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_function_set_description",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "descriptionRaw", type: .intptr),
                RuntimeABIParameter(name: "identity", type: .intptr),
            ],
            returnType: .void,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_tag_kfunction",
            parameters: [
                RuntimeABIParameter(name: "callable", type: .intptr),
                RuntimeABIParameter(name: "name", type: .intptr),
                RuntimeABIParameter(name: "returnType", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_tag_kproperty",
            parameters: [
                RuntimeABIParameter(name: "callable", type: .intptr),
                RuntimeABIParameter(name: "name", type: .intptr),
                RuntimeABIParameter(name: "returnType", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
    ]
}
