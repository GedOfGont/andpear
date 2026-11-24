import java.awt.*;
import java.awt.geom.RoundRectangle2D;
import java.awt.image.BufferedImage;
import java.io.File;
import javax.imageio.ImageIO;

/** Extracts the white "N" from the generated icon as an alpha mask and rebuilds clean icons around it. */
public class MakeIcons {
    static final int CROP = 1500, CX = 1024, CY = 1024;      // region around the N in the 2048 source
    static final double N_FRAC = 1016.0 / CROP;               // N width as a fraction of the crop

    static BufferedImage src;
    static int[] c1, c2;                                      // gradient end colours (dark TL -> bright BR)

    static int[] avg(int x0, int y0) {
        long r = 0, g = 0, b = 0; int n = 0;
        for (int y = y0; y < y0 + 20; y++) for (int x = x0; x < x0 + 20; x++) {
            int p = src.getRGB(x, y); r += (p >> 16) & 255; g += (p >> 8) & 255; b += p & 255; n++;
        }
        return new int[]{(int) (r / n), (int) (g / n), (int) (b / n)};
    }

    /** White N with alpha taken from the green channel (the purple background has ~0 green). */
    static BufferedImage nMask() {
        BufferedImage m = new BufferedImage(CROP, CROP, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < CROP; y++) for (int x = 0; x < CROP; x++) {
            int p = src.getRGB(x + CX - CROP / 2, y + CY - CROP / 2);
            int g = (p >> 8) & 255;
            int a = Math.max(0, Math.min(255, (int) ((g - 10) * 255.0 / 235.0)));
            m.setRGB(x, y, (a << 24) | 0xFFFFFF);
        }
        return m;
    }

    static BufferedImage gradient(int size) {
        BufferedImage img = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        g.setPaint(new GradientPaint(0, 0, new Color(c1[0], c1[1], c1[2]), size, size, new Color(c2[0], c2[1], c2[2])));
        g.fillRect(0, 0, size, size);
        g.dispose();
        return img;
    }

    static Graphics2D hq(BufferedImage i) {
        Graphics2D g = i.createGraphics();
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC);
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON);
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY);
        return g;
    }

    /** Draws the N centred so its width is nWidth pixels. */
    static void drawN(Graphics2D g, BufferedImage mask, double cx, double cy, double nWidth) {
        double side = nWidth / N_FRAC;
        g.drawImage(mask, (int) (cx - side / 2), (int) (cy - side / 2), (int) side, (int) side, null);
    }

    static void save(BufferedImage i, String path) throws Exception {
        new File(path).getParentFile().mkdirs();
        ImageIO.write(i, "png", new File(path));
    }

    static BufferedImage scaled(BufferedImage in, int size) {
        BufferedImage o = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = hq(o);
        g.drawImage(in, 0, 0, size, size, null);
        g.dispose();
        return o;
    }

    /** Fades the outermost `edge` pixels to transparent so the crop blends into the extended background. */
    static BufferedImage feather(BufferedImage im, int edge) {
        int n = im.getWidth();
        BufferedImage o = new BufferedImage(n, n, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < n; y++) for (int x = 0; x < n; x++) {
            int d = Math.min(Math.min(x, y), Math.min(n - 1 - x, n - 1 - y));
            double f = Math.min(1.0, d / (double) edge);
            int p = im.getRGB(x, y);
            int al = (int) (((p >>> 24) & 255) * f * f * (3 - 2 * f));
            o.setRGB(x, y, (al << 24) | (p & 0xFFFFFF));
        }
        return o;
    }

    static int px(BufferedImage im, int x, int y) { return im.getRGB(x, y); }

    /** Bilinear blend of the crop's four corner colours, used only to extend the background past the crop. */
    static BufferedImage extendedBackground(BufferedImage crop, int size) {
        int m = 4, w = crop.getWidth() - 1;
        int[] tl = ch(px(crop, m, m)), tr = ch(px(crop, w - m, m)), bl = ch(px(crop, m, w - m)), br = ch(px(crop, w - m, w - m));
        BufferedImage o = new BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB);
        for (int y = 0; y < size; y++) for (int x = 0; x < size; x++) {
            double u = x / (size - 1.0), v = y / (size - 1.0);
            int rgb = 0xFF000000;
            for (int c = 0; c < 3; c++) {
                double top = tl[c] + (tr[c] - tl[c]) * u, bot = bl[c] + (br[c] - bl[c]) * u;
                rgb |= (int) Math.round(top + (bot - top) * v) << (16 - 8 * c);
            }
            o.setRGB(x, y, rgb);
        }
        return o;
    }

    static int[] ch(int p) { return new int[]{(p >> 16) & 255, (p >> 8) & 255, p & 255}; }

    public static void main(String[] a) throws Exception {
        src = ImageIO.read(new File(a[0]));
        String out = a[1];
        final int L = a.length > 2 ? Integer.parseInt(a[2]) : 1800;
        BufferedImage crop = src.getSubimage(CX - L / 2, CY - L / 2, L, L);

        // Android adaptive icon: original art shrunk to 72% of the layer, background extended around it
        BufferedImage layer = extendedBackground(crop, 432);
        Graphics2D g = hq(layer);
        int side = (int) (432 * 0.72);
        g.drawImage(feather(scaled(crop, side), 28), (432 - side) / 2, (432 - side) / 2, null);
        g.dispose();
        save(layer, out + "/android/ic_launcher_bg.png");

        // Play Store
        save(scaled(crop, 512), out + "/play-icon-512.png");

        // macOS: original art in a rounded square with the standard margin
        BufferedImage mac = new BufferedImage(1024, 1024, BufferedImage.TYPE_INT_ARGB);
        g = hq(mac);
        // full-bleed opaque square: macOS applies its own mask, so no margin or rounded corners here
        g.drawImage(crop, 0, 0, 1024, 1024, null);
        g.dispose();
        save(mac, out + "/mac-1024.png");
    }
}
