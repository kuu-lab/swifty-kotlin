import kotlinx.io.Buffer;

public final class BufferHeadJavaSourceNegative {
    public static void main(String[] args) {
        Buffer buffer = new Buffer();
        buffer.getHead();
        buffer.setHead(null);
    }
}
