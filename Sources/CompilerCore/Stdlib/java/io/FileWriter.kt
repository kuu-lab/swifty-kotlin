package java.io

import kotlinx.io.asOutputStream
import kotlinx.io.buffered
import kotlinx.io.files.Path as IoPath
import kotlinx.io.files.SystemFileSystem

private fun fileOutputStream(file: File, append: Boolean): OutputStream =
    SystemFileSystem.sink(IoPath(file.path), append).buffered().asOutputStream()

public class FileWriter : OutputStreamWriter {
    public constructor(file: File) : super(fileOutputStream(file, false), Charsets.UTF_8)

    public constructor(file: File, append: Boolean) : super(fileOutputStream(file, append), Charsets.UTF_8)

    public constructor(file: File, charset: Charset) : super(fileOutputStream(file, false), charset)

    public constructor(file: File, append: Boolean, charset: Charset) : super(fileOutputStream(file, append), charset)

    public constructor(fileName: String) : this(File(fileName))

    public constructor(fileName: String, append: Boolean) : this(File(fileName), append)

    public constructor(fileName: String, charset: Charset) : this(File(fileName), charset)

    public constructor(fileName: String, append: Boolean, charset: Charset) : this(File(fileName), append, charset)
}
