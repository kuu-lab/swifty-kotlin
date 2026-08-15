import RuntimeABI

/// FileIO lookup names for `CollectionLiteralLookupTables`.
///
/// Split out from `CollectionLiteralLoweringPass+LookupTables.swift`.
struct FileIOLookupNames {
    // Shared member names used by File I/O (STDLIB-565)
    let deleteName: InternedString
    let lengthName: InternedString
    // File I/O names (STDLIB-565)
    let fileConstructorName: InternedString
    let kkFileNewName: InternedString
    let readTextName: InternedString
    let kkFileReadTextName: InternedString
    let writeTextName: InternedString
    let kkFileWriteTextName: InternedString
    let appendTextName: InternedString
    let kkFileAppendTextName: InternedString
    let existsName: InternedString
    let kkFileExistsName: InternedString
    let isFileName: InternedString
    let kkFileIsFileName: InternedString
    let isDirectoryName: InternedString
    let kkFileIsDirectoryName: InternedString
    let kkBufferedReaderForEachLineName: InternedString
    // STDLIB-IO-FN-016: File.forEachBlock
    let forEachBlockName: InternedString
    let kkFileForEachBlockName: InternedString
    let kkFileForEachBlockBlockSizeName: InternedString
    let kkBufferedReaderUseLinesName: InternedString
    let kkPathUseLinesName: InternedString
    let kkPathUseLinesDefaultName: InternedString
    // STDLIB-IO-PATH-FN-039: Path.walk(options) → kk_path_walk
    let kkPathWalkName: InternedString
    let bufferedReaderName: InternedString
    let kkFileBufferedReaderName: InternedString
    let bufferedWriterName: InternedString
    let kkFileBufferedWriterName: InternedString
    let kkFileDeleteName: InternedString
    let mkdirsName: InternedString
    let kkFileMkdirsName: InternedString
    let listFilesName: InternedString
    let kkFileListFilesName: InternedString
    let walkName: InternedString
    let kkFileWalkName: InternedString
    let readBytesName: InternedString
    let kkFileReadBytesName: InternedString
    // STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)
    let appendBytesName: InternedString
    let kkFileAppendBytesName: InternedString
    // MIGRATION-IO-001: File.writeBytes(array: ByteArray)
    let writeBytesName: InternedString
    let kkFileWriteBytesName: InternedString
    // STDLIB-IO-087: Additional File operations
    let absolutePathName: InternedString
    let kkFileAbsolutePathName: InternedString
    let canonicalPathName: InternedString
    let kkFileCanonicalPathName: InternedString
    let kkFileLengthName: InternedString
    let lastModifiedName: InternedString
    let kkFileLastModifiedName: InternedString
    let createNewFileName: InternedString
    let kkFileCreateNewFileName: InternedString
    let canReadName: InternedString
    let kkFileCanReadName: InternedString
    let canWriteName: InternedString
    let kkFileCanWriteName: InternedString
    let canExecuteName: InternedString
    let kkFileCanExecuteName: InternedString
    let kkFileNewParentChildName: InternedString
    // STDLIB-IO-FN-027: PrintWriter
    let printWriterName: InternedString
    let kkFilePrintWriterName: InternedString

    init(interner: StringInterner) {
        // Shared member names used by File I/O (STDLIB-565)
        deleteName = interner.intern("delete")
        lengthName = interner.intern("length")
        // File I/O names (STDLIB-565)
        fileConstructorName = interner.intern("File")
        kkFileNewName = interner.intern("__kk_file_new")
        readTextName = interner.intern("readText")
        kkFileReadTextName = interner.intern("__kk_file_readText")
        writeTextName = interner.intern("writeText")
        kkFileWriteTextName = interner.intern("__kk_file_writeText")
        appendTextName = interner.intern("appendText")
        kkFileAppendTextName = interner.intern("__kk_file_appendText")
        existsName = interner.intern("exists")
        kkFileExistsName = interner.intern("__kk_file_exists")
        isFileName = interner.intern("isFile")
        kkFileIsFileName = interner.intern("__kk_file_isFile")
        isDirectoryName = interner.intern("isDirectory")
        kkFileIsDirectoryName = interner.intern("__kk_file_isDirectory")
        kkBufferedReaderForEachLineName = interner.intern("__kk_buffered_reader_forEachLine")
        // STDLIB-IO-FN-016: File.forEachBlock
        forEachBlockName = interner.intern("forEachBlock")
        kkFileForEachBlockName = interner.intern("__kk_file_forEachBlock")
        kkFileForEachBlockBlockSizeName = interner.intern("__kk_file_forEachBlock_blockSize")
        kkBufferedReaderUseLinesName = interner.intern("__kk_buffered_reader_useLines")
        kkPathUseLinesName = interner.intern("kk_path_useLines")
        kkPathUseLinesDefaultName = interner.intern("kk_path_useLines_default")
        // STDLIB-IO-PATH-FN-039
        kkPathWalkName = interner.intern("kk_path_walk")
        bufferedReaderName = interner.intern("bufferedReader")
        kkFileBufferedReaderName = interner.intern("__kk_file_bufferedReader")
        bufferedWriterName = interner.intern("bufferedWriter")
        kkFileBufferedWriterName = interner.intern("__kk_file_bufferedWriter")
        kkFileDeleteName = interner.intern("__kk_file_delete")
        mkdirsName = interner.intern("mkdirs")
        kkFileMkdirsName = interner.intern("__kk_file_mkdirs")
        listFilesName = interner.intern("listFiles")
        kkFileListFilesName = interner.intern("__kk_file_listFiles")
        walkName = interner.intern("walk")
        kkFileWalkName = interner.intern("__kk_file_walk")
        readBytesName = interner.intern("readBytes")
        kkFileReadBytesName = interner.intern("__kk_file_readBytes")
        // STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)
        appendBytesName = interner.intern("appendBytes")
        kkFileAppendBytesName = interner.intern("__kk_file_appendBytes")
        // MIGRATION-IO-001: File.writeBytes(array: ByteArray)
        writeBytesName = interner.intern("writeBytes")
        kkFileWriteBytesName = interner.intern("__kk_file_writeBytes")
        // STDLIB-IO-087: Additional File operations
        absolutePathName = interner.intern("absolutePath")
        kkFileAbsolutePathName = interner.intern("__kk_file_absolutePath")
        canonicalPathName = interner.intern("canonicalPath")
        kkFileCanonicalPathName = interner.intern("__kk_file_canonicalPath")
        // lengthName already initialized in StringBuilder section above
        kkFileLengthName = interner.intern("__kk_file_length")
        lastModifiedName = interner.intern("lastModified")
        kkFileLastModifiedName = interner.intern("__kk_file_lastModified")
        createNewFileName = interner.intern("createNewFile")
        kkFileCreateNewFileName = interner.intern("__kk_file_createNewFile")
        canReadName = interner.intern("canRead")
        kkFileCanReadName = interner.intern("__kk_file_canRead")
        canWriteName = interner.intern("canWrite")
        kkFileCanWriteName = interner.intern("__kk_file_canWrite")
        canExecuteName = interner.intern("canExecute")
        kkFileCanExecuteName = interner.intern("__kk_file_canExecute")
        kkFileNewParentChildName = interner.intern("__kk_file_new_parent_child")
        // STDLIB-IO-FN-027: PrintWriter
        printWriterName = interner.intern("printWriter")
        kkFilePrintWriterName = interner.intern("__kk_file_printWriter")
    }
}
