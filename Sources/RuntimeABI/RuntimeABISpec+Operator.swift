// swiftlint:disable file_length

public extension RuntimeABISpec {
    static let opIsSpec: RuntimeABIFunctionSpec = RuntimeABIFunctionSpec(
        name: "kk_op_is",
        parameters: [
            RuntimeABIParameter(name: "value", type: .intptr),
            RuntimeABIParameter(name: "typeToken", type: .intptr),
        ],
        returnType: .intptr,
        section: "TypeCheck",
        isThrowing: false
    )


    static let operatorFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_type_register_super",
            parameters: [
                RuntimeABIParameter(name: "childTypeId", type: .intptr),
                RuntimeABIParameter(name: "superTypeId", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_type_register_iface",
            parameters: [
                RuntimeABIParameter(name: "childTypeId", type: .intptr),
                RuntimeABIParameter(name: "ifaceTypeId", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_itable_iface",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "ifaceTypeId", type: .intptr),
                RuntimeABIParameter(name: "ifaceSlot", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_itable_method",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "ifaceSlot", type: .intptr),
                RuntimeABIParameter(name: "methodSlot", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_vtable_method",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "methodSlot", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_equals_override",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_hashcode_override",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_any_to_string",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_value_class_register_any_to_string",
            parameters: [
                RuntimeABIParameter(name: "classID", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_type_token_simple_name",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_type_token_qualified_name",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_create",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_of",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "fallbackToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_simple_name",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_qualified_name",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_display_name",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "displayNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_object",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "initializerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_object_instance",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_sealed_subclass",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "subclassToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_sealed_subclasses",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_metadata",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "qualifiedNameRaw", type: .intptr),
                RuntimeABIParameter(name: "simpleNameRaw", type: .intptr),
                RuntimeABIParameter(name: "supertypeNameRaw", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
                RuntimeABIParameter(name: "fieldCount", type: .intptr),
                RuntimeABIParameter(name: "memberCount", type: .intptr),
                RuntimeABIParameter(name: "constructorCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_data",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_sealed",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_value",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_interface",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_object",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_enum",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_abstract",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_inner",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_companion",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_fun",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_get_annotations_typed",
            parameters: [RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                         RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)],
            returnType: .intptr, section: "Reflection", isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_find_annotation_typed",
            parameters: ["kclassRaw", "typeToken"].map { RuntimeABIParameter(name: $0, type: .intptr) }
                + [RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)],
            returnType: .intptr, section: "Reflection", isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_annotation_factory",
            parameters: ["typeToken", "fqNameRaw", "argsEncodedRaw", "argCount", "factory"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            }, returnType: .intptr, section: "Reflection", isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_runtime",
            parameters: [RuntimeABIParameter(name: "raw", type: .intptr)],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_get_annotations",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_find_associated_object",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "keyNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_single_annotation",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "fqNameRaw", type: .intptr),
                RuntimeABIParameter(name: "argsEncodedRaw", type: .intptr),
                RuntimeABIParameter(name: "argCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_isInstance",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_cast",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_safeCast",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_get_declared_methods",
            parameters: [
                RuntimeABIParameter(name: "classRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_get_declared_method",
            parameters: [
                RuntimeABIParameter(name: "classRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "parameterTypesRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_get_declared_field",
            parameters: [
                RuntimeABIParameter(name: "classRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_get_annotations_typed",
            parameters: [
                RuntimeABIParameter(name: "classRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_register_inherited_annotation",
            parameters: [
                RuntimeABIParameter(name: "annotationNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_get_name",
            parameters: [
                RuntimeABIParameter(name: "classRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_register_declared_method",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "methodNameRaw", type: .intptr),
                RuntimeABIParameter(name: "signatureRaw", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_class_register_declared_field",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "fieldNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_field_register_single_annotation",
            parameters: ["typeToken", "fieldNameRaw", "fqNameRaw", "argsEncodedRaw", "argCount"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            },
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_field_register_annotation_factory",
            parameters: ["typeToken", "fieldNameRaw", "fqNameRaw", "argsEncodedRaw", "argCount", "factory"].map {
                RuntimeABIParameter(name: $0, type: .intptr)
            },
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_field_get_annotations_typed",
            parameters: [
                RuntimeABIParameter(name: "fieldRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_method_get_name",
            parameters: [
                RuntimeABIParameter(name: "methodRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_method_get_return_type",
            parameters: [
                RuntimeABIParameter(name: "methodRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_java_method_is_synthetic",
            parameters: [
                RuntimeABIParameter(name: "methodRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_members",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_constructors",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // MIGRATION-REFLECT-002: KClass.nestedClasses
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_nested_classes",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_companion_object",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_companion",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "companionToken", type: .intptr),
                RuntimeABIParameter(name: "companionNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_nested_class",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nestedToken", type: .intptr),
                RuntimeABIParameter(name: "nestedNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_primary_constructor",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),

        RuntimeABIFunctionSpec(
            name: "__kk_kclass_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_member_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_declared_member_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_member_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_declared_member_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktype_classifier",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktype_arguments",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktype_isMarkedNullable",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktype_create",
            parameters: [
                RuntimeABIParameter(name: "classifierRaw", type: .intptr),
                RuntimeABIParameter(name: "argsRaw", type: .intptr),
                RuntimeABIParameter(name: "isNullable", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeparameter_create",
            parameters: [
                RuntimeABIParameter(name: "identity", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "varianceOrdinal", type: .intptr),
                RuntimeABIParameter(name: "isReified", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeparameter_set_upper_bounds",
            parameters: [
                RuntimeABIParameter(name: "parameterRaw", type: .intptr),
                RuntimeABIParameter(name: "boundsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeparameter_is_runtime",
            parameters: [
                RuntimeABIParameter(name: "parameterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeparameter_get_name",
            parameters: [
                RuntimeABIParameter(name: "parameterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeprojection_create",
            parameters: [
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "varianceOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeprojection_create_checked",
            parameters: [
                RuntimeABIParameter(name: "varianceOrdinal", type: .intptr),
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeprojection_star",
            parameters: [],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeprojection_get_variance",
            parameters: [
                RuntimeABIParameter(name: "projectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeprojection_get_type",
            parameters: [
                RuntimeABIParameter(name: "projectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_typeof",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
                RuntimeABIParameter(name: "argsRaw", type: .intptr),
                RuntimeABIParameter(name: "isNullable", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        opIsSpec,
        RuntimeABIFunctionSpec(
            name: "kk_op_cast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_cast_erased_return",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_safe_cast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_op_cast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "componentType", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_op_safe_cast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "componentType", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_contains",
            parameters: [
                RuntimeABIParameter(name: "container", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
    ]
}
