package kotlinx.io;

public interface Source {
    Buffer getBuffer();
    void require(long byteCount);
    boolean request(long byteCount);
    void skip(long byteCount);
}
