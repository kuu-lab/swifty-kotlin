/// `RuntimeABISpec.fileSystemExceptionFunctions` (KSP-619): storage bridges for
/// the `kotlin.io` filesystem exception hierarchy declared in
/// `Stdlib/kotlin/io/FileSystemException.kt`.
///
/// Each class gets one constructor entry point per arity so that the allocated
/// box carries the runtime type identity catch-clause dispatch (`kk_op_is`)
/// needs, plus shared `file` / `other` / `reason` accessors.
public extension RuntimeABISpec {
    // MARK: - kotlin.io filesystem exceptions (KSP-619)

    private static let fileSystemExceptionPrefixes = [
        "file_system",
        "file_already_exists",
        "access_denied",
        "no_such_file",
    ]

    static let fileSystemExceptionFunctions: [RuntimeABIFunctionSpec] =
        fileSystemExceptionPrefixes.flatMap { prefix -> [RuntimeABIFunctionSpec] in
            [
                RuntimeABIFunctionSpec(
                    name: "__kk_\(prefix)_exception_new_file",
                    parameters: [
                        RuntimeABIParameter(name: "fileRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "FileSystemException",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_\(prefix)_exception_new_file_other",
                    parameters: [
                        RuntimeABIParameter(name: "fileRaw", type: .intptr),
                        RuntimeABIParameter(name: "otherRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "FileSystemException",
                    isThrowing: false
                ),
                RuntimeABIFunctionSpec(
                    name: "__kk_\(prefix)_exception_new_file_other_reason",
                    parameters: [
                        RuntimeABIParameter(name: "fileRaw", type: .intptr),
                        RuntimeABIParameter(name: "otherRaw", type: .intptr),
                        RuntimeABIParameter(name: "reasonRaw", type: .intptr),
                    ],
                    returnType: .intptr,
                    section: "FileSystemException",
                    isThrowing: false
                ),
            ]
        } + [
            RuntimeABIFunctionSpec(
                name: "__kk_file_system_exception_file",
                parameters: [
                    RuntimeABIParameter(name: "selfRaw", type: .intptr),
                ],
                returnType: .intptr,
                section: "FileSystemException",
                isThrowing: false
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_file_system_exception_other",
                parameters: [
                    RuntimeABIParameter(name: "selfRaw", type: .intptr),
                ],
                returnType: .intptr,
                section: "FileSystemException",
                isThrowing: false
            ),
            RuntimeABIFunctionSpec(
                name: "__kk_file_system_exception_reason",
                parameters: [
                    RuntimeABIParameter(name: "selfRaw", type: .intptr),
                ],
                returnType: .intptr,
                section: "FileSystemException",
                isThrowing: false
            ),
        ]
}
