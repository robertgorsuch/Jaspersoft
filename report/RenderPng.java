import net.sf.jasperreports.engine.JasperFillManager;
import net.sf.jasperreports.engine.JasperPrint;
import net.sf.jasperreports.engine.JasperPrintManager;
import javax.imageio.ImageIO;
import java.awt.Image;
import java.awt.image.BufferedImage;
import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.util.HashMap;

// Fill a .jasper against the DB and render one page to PNG (for visual checks).
//   java --class-path "<lib>\*" RenderPng.java <file.jasper> <out.png> [pageIndex]
public class RenderPng {
    public static void main(String[] args) throws Exception {
        String jasper = args[0];
        String png = args[1];
        int page = args.length > 2 ? Integer.parseInt(args[2]) : 0;
        Class.forName("org.postgresql.Driver");
        Connection conn = DriverManager.getConnection(
            System.getProperty("db.url", "jdbc:postgresql://localhost:5432/postgis_34_sample"),
            System.getProperty("db.user", "postgres"), System.getenv("PGPASSWORD"));
        try {
            JasperPrint jp = JasperFillManager.fillReport(jasper, new HashMap<>(), conn);
            Image img = JasperPrintManager.printPageToImage(jp, page, 1.5f);
            ImageIO.write((BufferedImage) img, "png", new File(png));
            System.out.println("OK: " + png + " | pages=" + jp.getPages().size());
        } finally {
            conn.close();
        }
    }
}
