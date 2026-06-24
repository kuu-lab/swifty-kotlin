package kotlin.io

// MIGRATION-IO-002
// File stream and buffer extension functions.
// Migration source: Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticFileIOStubs.swift
//   (registerSyntheticFileIOStubs — bufferedReader, bufferedWriter, inputStream, outputStream,
//    Reader / Writer / InputStream / OutputStream extension registrations)
//
// Runtime implementations: Sources/Runtime/RuntimeFileIO.swift
//   kk_file_bufferedReader, kk_file_bufferedWriter, kk_file_inputStream, kk_file_outputStream,
//   kk_input_stream_bufferedReader, kk_input_stream_buffered, kk_input_stream_copyTo,
//   kk_output_stream_bufferedWriter, kk_output_stream_buffered, kk_output_stream_buffered_sized,
//   kk_writer_buffered_default, kk_writer_buffered,
//   kk_reader_readText, kk_reader_copyTo, kk_reader_copyTo_default
//
// NOTE: Not yet wired into the compiler pipeline (RF-STDLIB-004+).
// Sema stubs in HeaderHelpers+SyntheticFileIOStubs.swift still dispatch directly to the
// kk_* ABI functions. This file is the migration target; wiring (and removal of the
// corresponding synthetic stubs) happens in RF-STDLIB-004+.
//
// Implementation strategy:
//   - File.bufferedReader / bufferedWriter / inputStream / outputStream — ABI bridges
//   - File.reader / writer — pure Kotlin (delegate to inputStream/outputStream)
//   - InputStream / OutputStream / Reader / Writer extension functions — ABI bridges

import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.io.Reader
import java.io.Writer
import kotlin.text.Charset
import kotlin.text.Charsets

// Default buffer size used by buffered() and copyTo() overloads, matching the
// JVM stdlib constant `kotlin.io.DEFAULT_BUFFER_SIZE = 8 * 1024`.
public const val DEFAULT_BUFFER_SIZE: Int = 8 * 1024

// ─── ABI bridges ─────────────────────────────────────────────────────────────

private external fun kk_file_bufferedReader(file: File): BufferedReader
private external fun kk_file_bufferedWriter(file: File): BufferedWriter
private external fun kk_file_inputStream(file: File): InputStream
private external fun kk_file_outputStream(file: File): OutputStream

private external fun kk_input_stream_bufferedReader(stream: InputStream, charset: Any?): BufferedReader
private external fun kk_input_stream_buffered(stream: InputStream, bufferSize: Int): InputStream
private external fun kk_input_stream_copyTo(stream: InputStream, out: OutputStream, bufferSize: Int): Long

private external fun kk_output_stream_bufferedWriter(stream: OutputStream, charset: Any?): BufferedWriter
private external fun kk_output_stream_buffered(stream: OutputStream): OutputStream
private external fun kk_output_stream_buffered_sized(stream: OutputStream, bufferSize: Int): OutputStream

private external fun kk_writer_buffered_default(writer: Writer): BufferedWriter
private external fun kk_writer_buffered(writer: Writer, bufferSize: Int): BufferedWriter

private external fun kk_reader_readText(reader: Reader): String
private external fun kk_reader_copyTo(reader: Reader, writer: Writer, bufferSize: Int): Long
private external fun kk_reader_copyTo_default(reader: Reader, writer: Writer): Long

// ─── File extensions ──────────────────────────────────────────────────────────

public fun File.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader =
    kk_file_bufferedReader(this)

public fun File.bufferedWriter(charset: Charset = Charsets.UTF_8): BufferedWriter =
    kk_file_bufferedWriter(this)

public fun File.inputStream(): InputStream = kk_file_inputStream(this)

public fun File.outputStream(): OutputStream = kk_file_outputStream(this)

// reader() and writer() are pure Kotlin: compose inputStream/outputStream with the
// appropriate buffered wrapper. In JVM stdlib these return InputStreamReader /
// OutputStreamWriter; KSwiftK maps both to BufferedReader / BufferedWriter since
// InputStreamReader/OutputStreamWriter are not modelled as distinct types.
public fun File.reader(charset: Charset = Charsets.UTF_8): BufferedReader =
    inputStream().bufferedReader(charset)

public fun File.writer(charset: Charset = Charsets.UTF_8): BufferedWriter =
    outputStream().bufferedWriter(charset)

// ─── InputStream extensions ───────────────────────────────────────────────────

public fun InputStream.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader =
    kk_input_stream_bufferedReader(this, charset)

public fun InputStream.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): InputStream =
    kk_input_stream_buffered(this, bufferSize)

public fun InputStream.copyTo(out: OutputStream, bufferSize: Int = DEFAULT_BUFFER_SIZE): Long =
    kk_input_stream_copyTo(this, out, bufferSize)

// ─── OutputStream extensions ──────────────────────────────────────────────────

public fun OutputStream.bufferedWriter(charset: Charset = Charsets.UTF_8): BufferedWriter =
    kk_output_stream_bufferedWriter(this, charset)

public fun OutputStream.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): OutputStream =
    if (bufferSize == DEFAULT_BUFFER_SIZE) kk_output_stream_buffered(this)
    else kk_output_stream_buffered_sized(this, bufferSize)

// ─── Writer extensions ────────────────────────────────────────────────────────

public fun Writer.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): BufferedWriter =
    if (bufferSize == DEFAULT_BUFFER_SIZE) kk_writer_buffered_default(this)
    else kk_writer_buffered(this, bufferSize)

// ─── Reader extensions ────────────────────────────────────────────────────────

public fun Reader.readText(): String = kk_reader_readText(this)

public fun Reader.copyTo(out: Writer, bufferSize: Int = DEFAULT_BUFFER_SIZE): Long =
    if (bufferSize == DEFAULT_BUFFER_SIZE) kk_reader_copyTo_default(this, out)
    else kk_reader_copyTo(this, out, bufferSize)
