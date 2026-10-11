package java.nio.file

public class FileAlreadyExistsException(file: String) : java.io.IOException(file)
public class NoSuchFileException(file: String) : java.io.IOException(file)
