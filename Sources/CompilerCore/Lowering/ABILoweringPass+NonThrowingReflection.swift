extension ABILoweringPass {
    /// Reflection non-throwing callees: callable refs, KFunction, KParameter, KType, KClass, annotations.
    static func nonThrowingReflectionCallees(_ interner: StringInterner) -> [InternedString] {
        [
            // REFL-003: Callable reference type identity tagging — pure metadata
            // annotation that cannot throw.
            interner.intern("kk_callable_ref_tag_kfunction"),
            interner.intern("kk_callable_ref_tag_kproperty"),
            interner.intern("kk_callable_ref_name"),
            // STDLIB-REFLECT-063: KFunction reflection helpers.
            interner.intern("kk_callable_ref_arity"),
            interner.intern("kk_callable_ref_is_suspend"),
            interner.intern("kk_callable_ref_parameters"),
            // STDLIB-REFLECT-063: KFunction / KParameter reflection — pure metadata
            // lookups that cannot throw.
            interner.intern("kk_kfunction_get_name"),
            interner.intern("kk_kfunction_get_arity"),
            interner.intern("kk_kfunction_get_return_type"),
            interner.intern("kk_kfunction_is_suspend"),
            interner.intern("kk_kfunction_get_parameters"),
            interner.intern("kk_kfunction_get_value_parameters"),
            interner.intern("kk_kfunction_get_type"),
            interner.intern("kk_kfunction_create"),
            interner.intern("kk_kfunction_create_full"),
            interner.intern("kk_kparameter_create"),
            interner.intern("kk_kparameter_get_index"),
            interner.intern("kk_kparameter_get_name"),
            interner.intern("kk_kparameter_get_type"),
            interner.intern("kk_kparameter_is_optional"),
            interner.intern("kk_kparameter_get_kind"),
            // STDLIB-REFLECT-066: KType / KClass reflection — all are pure metadata
            // lookups that cannot throw.
            interner.intern("kk_typeof"),
            interner.intern("kk_ktype_create"),
            interner.intern("kk_ktype_classifier"),
            interner.intern("kk_ktype_arguments"),
            interner.intern("kk_ktype_isMarkedNullable"),
            interner.intern("kk_ktype_to_string"),
            interner.intern("kk_ktypeprojection_create"),
            interner.intern("kk_ktypeprojection_type"),
            interner.intern("kk_ktypeprojection_variance"),
            interner.intern("kk_kclass_create"),
            interner.intern("kk_kclass_simple_name"),
            interner.intern("kk_kclass_qualified_name"),
            interner.intern("kk_kclass_supertype_name"),
            interner.intern("kk_kclass_is_data"),
            interner.intern("kk_kclass_is_sealed"),
            interner.intern("kk_kclass_is_value"),
            interner.intern("kk_kclass_is_enum"),
            interner.intern("kk_kclass_is_interface"),
            interner.intern("kk_kclass_is_object"),
            interner.intern("kk_kclass_safeCast"),
            interner.intern("kk_kclass_members_count"),
            // STDLIB-REFLECT-060: KClass basic reflection non-throwing callees
            interner.intern("kk_kclass_is_final"),
            interner.intern("kk_kclass_is_open"),
            interner.intern("kk_kclass_is_abstract"),
            interner.intern("kk_kclass_visibility"),
            interner.intern("kk_kclass_type_parameters"),
            interner.intern("kk_kclass_supertypes"),
            // STDLIB-REFLECT-067: KClass type-kind introspection non-throwing callees
            interner.intern("kk_kclass_is_inner"),
            interner.intern("kk_kclass_is_companion"),
            interner.intern("kk_kclass_is_fun"),
            // STDLIB-REFLECT-065: Annotation reflection
            interner.intern("kk_annotation_create"),
            interner.intern("kk_annotation_get_class"),
            interner.intern("kk_annotation_get_fqname"),
            interner.intern("kk_annotation_get_value"),
            interner.intern("kk_annotation_get_arg_count"),
            interner.intern("kk_annotation_to_string"),
            interner.intern("kk_kclass_get_annotations"),
            interner.intern("kk_kclass_find_annotation"),
            interner.intern("kk_kclass_register_single_annotation"),
        ]
    }
}
