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
    let readLinesName: InternedString
    let kkFileReadLinesName: InternedString
    let existsName: InternedString
    let kkFileExistsName: InternedString
    let isFileName: InternedString
    let kkFileIsFileName: InternedString
    let isDirectoryName: InternedString
    let kkFileIsDirectoryName: InternedString
    let forEachLineName: InternedString
    let kkFileForEachLineName: InternedString
    let kkBufferedReaderForEachLineName: InternedString
    // STDLIB-IO-FN-016: File.forEachBlock
    let forEachBlockName: InternedString
    let kkFileForEachBlockName: InternedString
    let kkFileForEachBlockBlockSizeName: InternedString
    let useLinesName: InternedString
    let kkFileUseLinesName: InternedString
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
    // STDLIB-IO-PATH-FN-039: File.walk(direction:) → kk_file_walk_with_direction
    let kkFileWalkWithDirectionName: InternedString
    // STDLIB-IO-TYPE-004: FileTreeWalk
    let walkTopDownName: InternedString
    let kkFileWalkTopDownName: InternedString
    let walkBottomUpName: InternedString
    let kkFileWalkBottomUpName: InternedString
    let kkFileTreeWalkMaxDepthName: InternedString
    let kkFileTreeWalkToListName: InternedString
    let kkFileTreeWalkOnEnterName: InternedString
    let kkFileTreeWalkOnLeaveName: InternedString
    let kkFileTreeWalkOnFailName: InternedString
    let kkFileTreeWalkForEachName: InternedString
    let kkFileTreeWalkFilterName: InternedString
    let kkFileTreeWalkSortedByName: InternedString
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
        kkFileNewName = interner.intern("kk_file_new")
        readTextName = interner.intern("readText")
        kkFileReadTextName = interner.intern("kk_file_readText")
        writeTextName = interner.intern("writeText")
        kkFileWriteTextName = interner.intern("kk_file_writeText")
        appendTextName = interner.intern("appendText")
        kkFileAppendTextName = interner.intern("kk_file_appendText")
        readLinesName = interner.intern("readLines")
        kkFileReadLinesName = interner.intern("kk_file_readLines")
        existsName = interner.intern("exists")
        kkFileExistsName = interner.intern("kk_file_exists")
        isFileName = interner.intern("isFile")
        kkFileIsFileName = interner.intern("kk_file_isFile")
        isDirectoryName = interner.intern("isDirectory")
        kkFileIsDirectoryName = interner.intern("kk_file_isDirectory")
        forEachLineName = interner.intern("forEachLine")
        kkFileForEachLineName = interner.intern("kk_file_forEachLine")
        kkBufferedReaderForEachLineName = interner.intern("kk_buffered_reader_forEachLine")
        // STDLIB-IO-FN-016: File.forEachBlock
        forEachBlockName = interner.intern("forEachBlock")
        kkFileForEachBlockName = interner.intern("kk_file_forEachBlock")
        kkFileForEachBlockBlockSizeName = interner.intern("kk_file_forEachBlock_blockSize")
        useLinesName = interner.intern("useLines")
        kkFileUseLinesName = interner.intern("kk_file_useLines")
        kkBufferedReaderUseLinesName = interner.intern("kk_buffered_reader_useLines")
        kkPathUseLinesName = interner.intern("kk_path_useLines")
        kkPathUseLinesDefaultName = interner.intern("kk_path_useLines_default")
        // STDLIB-IO-PATH-FN-039
        kkPathWalkName = interner.intern("kk_path_walk")
        bufferedReaderName = interner.intern("bufferedReader")
        kkFileBufferedReaderName = interner.intern("kk_file_bufferedReader")
        bufferedWriterName = interner.intern("bufferedWriter")
        kkFileBufferedWriterName = interner.intern("kk_file_bufferedWriter")
        kkFileDeleteName = interner.intern("kk_file_delete")
        mkdirsName = interner.intern("mkdirs")
        kkFileMkdirsName = interner.intern("kk_file_mkdirs")
        listFilesName = interner.intern("listFiles")
        kkFileListFilesName = interner.intern("kk_file_listFiles")
        walkName = interner.intern("walk")
        kkFileWalkName = interner.intern("kk_file_walk")
        // STDLIB-IO-PATH-FN-039: File.walk(direction:) → kk_file_walk_with_direction
        kkFileWalkWithDirectionName = interner.intern("kk_file_walk_with_direction")
        // STDLIB-IO-TYPE-004: FileTreeWalk
        walkTopDownName = interner.intern("walkTopDown")
        kkFileWalkTopDownName = interner.intern("kk_file_walkTopDown")
        walkBottomUpName = interner.intern("walkBottomUp")
        kkFileWalkBottomUpName = interner.intern("kk_file_walkBottomUp")
        kkFileTreeWalkMaxDepthName = interner.intern("kk_file_tree_walk_max_depth")
        kkFileTreeWalkToListName = interner.intern("kk_file_tree_walk_to_list")
        kkFileTreeWalkOnEnterName = interner.intern("kk_file_tree_walk_onEnter")
        kkFileTreeWalkOnLeaveName = interner.intern("kk_file_tree_walk_onLeave")
        kkFileTreeWalkOnFailName = interner.intern("kk_file_tree_walk_onFail")
        kkFileTreeWalkForEachName = interner.intern("kk_file_tree_walk_forEach")
        kkFileTreeWalkFilterName = interner.intern("kk_file_tree_walk_filter")
        kkFileTreeWalkSortedByName = interner.intern("kk_file_tree_walk_sortedBy")
        readBytesName = interner.intern("readBytes")
        kkFileReadBytesName = interner.intern("kk_file_readBytes")
        // STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)
        appendBytesName = interner.intern("appendBytes")
        kkFileAppendBytesName = interner.intern("kk_file_appendBytes")
        // MIGRATION-IO-001: File.writeBytes(array: ByteArray)
        writeBytesName = interner.intern("writeBytes")
        kkFileWriteBytesName = interner.intern("kk_file_writeBytes")
        // STDLIB-IO-087: Additional File operations
        absolutePathName = interner.intern("absolutePath")
        kkFileAbsolutePathName = interner.intern("kk_file_absolutePath")
        canonicalPathName = interner.intern("canonicalPath")
        kkFileCanonicalPathName = interner.intern("kk_file_canonicalPath")
        // lengthName already initialized in StringBuilder section above
        kkFileLengthName = interner.intern("kk_file_length")
        lastModifiedName = interner.intern("lastModified")
        kkFileLastModifiedName = interner.intern("kk_file_lastModified")
        createNewFileName = interner.intern("createNewFile")
        kkFileCreateNewFileName = interner.intern("kk_file_createNewFile")
        canReadName = interner.intern("canRead")
        kkFileCanReadName = interner.intern("kk_file_canRead")
        canWriteName = interner.intern("canWrite")
        kkFileCanWriteName = interner.intern("kk_file_canWrite")
        canExecuteName = interner.intern("canExecute")
        kkFileCanExecuteName = interner.intern("kk_file_canExecute")
        kkFileNewParentChildName = interner.intern("kk_file_new_parent_child")
        // STDLIB-IO-FN-027: PrintWriter
        printWriterName = interner.intern("printWriter")
        kkFilePrintWriterName = interner.intern("kk_file_printWriter")
    }
}
