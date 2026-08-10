package kotlin.io

import java.io.File
import kotlin.internal.KsSymbolName

// KSP-619: kotlin.io filesystem exception hierarchy.
//
// The classes below replace the synthetic registrations that used to live in
// HeaderHelpers+SyntheticKotlinIOExceptionStubs.swift / +SyntheticExceptionStubs.swift.
// Storage is allocated by the runtime — the same representation the runtime uses
// when it raises one of these exceptions itself (File.copyTo, Files.delete, …) —
// so `catch (e: T)` and the `file` / `other` / `reason` accessors behave
// identically for exceptions thrown from Kotlin and from the runtime.
//
// Each arity gets its own bridge instead of relying on default parameter values:
// default arguments of an external constructor are not materialized by the
// current lowering, and a `this(file, null, null)` delegation allocates a second
// (storage-less) instance, so both would strand `file`/`other`/`reason`.

/**
 * A base exception class for file system exceptions.
 *
 * @property file the file on which the failed operation was performed.
 * @property other the second file involved in the operation, if any.
 * @property reason the description of the error, if any.
 */
public open class FileSystemException : Exception {
    @KsSymbolName("__kk_file_system_exception_new_file")
    public constructor(file: File)

    @KsSymbolName("__kk_file_system_exception_new_file_other")
    public constructor(file: File, other: File?)

    @KsSymbolName("__kk_file_system_exception_new_file_other_reason")
    public constructor(file: File, other: File?, reason: String?)

    public val file: File
        get() = __kk_file_system_exception_file()

    public val other: File?
        get() = __kk_file_system_exception_other()

    public val reason: String?
        get() = __kk_file_system_exception_reason()

    @KsSymbolName("__kk_file_system_exception_file")
    private external fun __kk_file_system_exception_file(): File

    @KsSymbolName("__kk_file_system_exception_other")
    private external fun __kk_file_system_exception_other(): File?

    @KsSymbolName("__kk_file_system_exception_reason")
    private external fun __kk_file_system_exception_reason(): String?
}

/** An exception class which is used when some file to create or copy to already exists. */
public class FileAlreadyExistsException : FileSystemException {
    @KsSymbolName("__kk_file_already_exists_exception_new_file")
    public constructor(file: File)

    @KsSymbolName("__kk_file_already_exists_exception_new_file_other")
    public constructor(file: File, other: File?)

    @KsSymbolName("__kk_file_already_exists_exception_new_file_other_reason")
    public constructor(file: File, other: File?, reason: String?)
}

/** An exception class which is used when we have not enough access for some operation. */
public class AccessDeniedException : FileSystemException {
    @KsSymbolName("__kk_access_denied_exception_new_file")
    public constructor(file: File)

    @KsSymbolName("__kk_access_denied_exception_new_file_other")
    public constructor(file: File, other: File?)

    @KsSymbolName("__kk_access_denied_exception_new_file_other_reason")
    public constructor(file: File, other: File?, reason: String?)
}

/** An exception class which is used when file to copy does not exist. */
public class NoSuchFileException : FileSystemException {
    @KsSymbolName("__kk_no_such_file_exception_new_file")
    public constructor(file: File)

    @KsSymbolName("__kk_no_such_file_exception_new_file_other")
    public constructor(file: File, other: File?)

    @KsSymbolName("__kk_no_such_file_exception_new_file_other_reason")
    public constructor(file: File, other: File?, reason: String?)
}
