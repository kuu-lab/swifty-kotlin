package kotlinx.io;

public interface Buffer {
    long getSize();
    byte get(long index);
}
