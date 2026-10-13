## js_annotations CI evidence (KUU-1617)

Status: **fail**; SKIP removal ready: **false**.

Revision: `4838c0b14c1d4a3cb279a198a721bf8d1cac2f6f`; matrix run: `20261013T011325.074493Z-47be2c08`.

| Result | Cells |
|---|---:|
| pass | 56 |
| fail | 52 |
| timeout | 0 |
| not-run | 0 |

| Fixture | source/O0 | source/O2 | artifact/O0 | artifact/O2 |
|---|---|---|---|---|
| annotation_arguments | fail | fail | fail | fail |
| bare_create_instance | fail | fail | fail | fail |
| collection_imports | fail | fail | fail | fail |
| collection_marker_fqn | fail | fail | fail | fail |
| export_nonexportable | fail | fail | fail | fail |
| export_suspend | fail | fail | fail | fail |
| file_name_arguments | fail | fail | fail | fail |
| file_name_nonconstant | fail | fail | fail | fail |
| file_name_target | fail | fail | fail | fail |
| marker_as_file | fail | fail | fail | fail |
| marker_no_opt_in | fail | fail | fail | fail |
| no_opt_in | pass | pass | pass | pass |
| static_receivers | fail | fail | fail | fail |
| static_visibility_const | fail | fail | fail | fail |
| typed_view_properties | pass | pass | pass | pass |
| file_name_no_opt_in | pass | pass | pass | pass |
| marker_requirements | pass | pass | pass | pass |
| native_observations | pass | pass | pass | pass |
| reflection | pass | pass | pass | pass |
| static_accepted | pass | pass | pass | pass |
| typed_views | pass | pass | pass | pass |
| unbound_create_instance | pass | pass | pass | pass |
| views_map | pass | pass | pass | pass |
| views_set | pass | pass | pass | pass |
| views_readonly_array | pass | pass | pass | pass |
| views_typed_mutators | pass | pass | pass | pass |
| views_variance | pass | pass | pass | pass |

Runner regressions:

- test_run_candidate: pass (exit=0)
- test_run_matrix: pass (exit=0)
- test_summarize_evidence: pass (exit=0)

Failures:

- annotation_arguments: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-JS-ANNOTATION-TOO-MANY-ARGUMENTS, unmapped_expected_diagnostic_kind:TOO_MANY_ARGUMENTS
- bare_create_instance: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-0022
- collection_imports: compile_diagnostics_mismatch, unmapped_expected_diagnostic_kind:UNRESOLVED_IMPORT
- collection_marker_fqn: compile_diagnostics_mismatch, compile_exit_mismatch, unmapped_expected_diagnostic_kind:ANNOTATION_ARGUMENT_MUST_BE_CONST
- export_nonexportable: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-JS-EXPORT-NON-EXPORTABLE-TYPE, unmapped_expected_diagnostic_kind:NON_EXPORTABLE_TYPE
- export_suspend: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-JS-EXPORT-WRONG-DECLARATION, unmapped_expected_diagnostic_kind:WRONG_EXPORTED_DECLARATION
- file_name_arguments: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-ANNOTATION-ARGUMENT-TYPE, unmapped_expected_diagnostic_kind:ARGUMENT_TYPE_MISMATCH
- file_name_nonconstant: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-ANNOTATION-ARGUMENT-CONST, unmapped_expected_diagnostic_kind:ANNOTATION_ARGUMENT_MUST_BE_CONST
- file_name_target: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-ANNOTATION-TARGET, unmapped_expected_diagnostic_kind:WRONG_ANNOTATION_TARGET
- marker_as_file: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-ANNOTATION-ARGUMENT-ARITY, unknown_diagnostic_code:KSWIFTK-SEMA-ANNOTATION-TARGET, unmapped_expected_diagnostic_kind:TOO_MANY_ARGUMENTS, unmapped_expected_diagnostic_kind:WRONG_ANNOTATION_TARGET_WITH_USE_SITE_TARGET
- marker_no_opt_in: compile_diagnostics_mismatch
- static_receivers: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-JS-STATIC-NOT-IN-CLASS-COMPANION, unmapped_expected_diagnostic_kind:JS_STATIC_NOT_IN_CLASS_COMPANION
- static_visibility_const: compile_diagnostics_mismatch, unknown_diagnostic_code:KSWIFTK-SEMA-JS-STATIC-ON-CONST, unknown_diagnostic_code:KSWIFTK-SEMA-JS-STATIC-ON-NON-PUBLIC-MEMBER, unmapped_expected_diagnostic_kind:JS_STATIC_ON_CONST, unmapped_expected_diagnostic_kind:JS_STATIC_ON_NON_PUBLIC_MEMBER

Out of native lane (not candidate passes): original, js_dynamic_views, views_dynamic

Unexecuted: KSwiftK JS emission/consumer (outside native target); full Swift tests and full kotlinc diff corpus

Exact commands, compile/run stdout/stderr, exits, and timeouts are retained in the matrix run directory.
Coverage and KUU-1480 handoff: `docs/js-annotations-ci-evidence.md`.
