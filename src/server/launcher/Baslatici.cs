// SOKAK: Operasyon - Başlatıcı
// Oyun dosyalarını (SOKAK.pck) GitHub'dan parça parça indirir (kaldığı yerden devam eder),
// sürüm kontrolü yapar ve BAŞLAT düğmesiyle oyunu açar.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("SOKAK: Operasyon Başlatıcı")]
[assembly: AssemblyProduct("SOKAK: Operasyon")]
[assembly: AssemblyCompany("SOKAK")]
[assembly: AssemblyVersion("2.3.0.0")]
[assembly: AssemblyFileVersion("2.3.0.0")]

namespace Sokak
{
    class Part { public string Url; public long Size; }

    enum St { Checking, Downloading, Merging, Ready, Error }

    class Launcher : Form
    {
        const string MANIFEST = "https://raw.githubusercontent.com/taha123123224/sokak/main/version.json";
        const int BW = 820, BH = 480;               // tasarım ölçüsü (DPI ile ölçeklenir)

        static readonly Color OR = Color.FromArgb(255, 138, 31);
        static readonly Color OR2 = Color.FromArgb(255, 180, 92);
        static readonly Color ORD = Color.FromArgb(199, 90, 12);
        static readonly Color TX = Color.FromArgb(233, 236, 239);
        static readonly Color MUT = Color.FromArgb(154, 163, 173);
        static readonly Color DIM = Color.FromArgb(107, 116, 126);

        readonly string dir;
        float sc = 1f;
        Image bg;
        Font fTitle, fBig, fBtn, fLbl, fBody, fSmall;

        volatile St state = St.Checking;
        volatile string title = "SÜRÜM KONTROL EDİLİYOR";
        volatile string sub = "Sunucuya bağlanılıyor…";
        string err = "";
        volatile string version = "";
        long total = 1, done = 0;           // Interlocked
        int partIdx = 0, partCount = 0;
        bool cancel = false;

        // hız / kalan süre
        readonly Queue<KeyValuePair<double, long>> samples = new Queue<KeyValuePair<double, long>>();
        double speed = 0;
        readonly Stopwatch clock = Stopwatch.StartNew();
        float shown = 0;                    // yumuşatılmış ilerleme

        RectangleF rBtn, rClose, rMin;
        string hover = "";
        Point dragFrom; bool dragging;

        static readonly string[] TIPS = {
            "Kafadan vuruşlar gövdeye göre 2,5 kat daha fazla hasar verir.",
            "SCAR-H ve AK-47 ince duvarların arkasındaki rakibi delip vurabilir.",
            "Susturucu takılı silahla ateş edince haritada görünmezsin.",
            "Eklenti Paketi kasasından susturucu, nişangah ve lazer çıkabilir.",
            "Arkadaşlarını ARKADAŞLAR sekmesinden ekleyip odana davet edebilirsin.",
            "Hesabın bulutta saklanır; güncelleme sonrası her şey yerinde kalır.",
            "UMP-45 ile vurduğun rakip kısa süre yavaşlar.",
            "Çömelerek ateş etmek sekmeyi azaltır.",
        };
        int tip = 0; double tipT = 0;

        [DllImport("user32.dll")] static extern bool SetProcessDPIAware();

        [STAThread]
        static void Main()
        {
            try { SetProcessDPIAware(); } catch { }
            try { ServicePointManager.SecurityProtocol = (SecurityProtocolType)3072; } catch { }
            ServicePointManager.DefaultConnectionLimit = 8;
            Application.EnableVisualStyles();
            Application.Run(new Launcher());
        }

        public Launcher()
        {
            dir = Path.GetDirectoryName(Application.ExecutablePath);
            Text = "SOKAK: Operasyon";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.FromArgb(12, 14, 17);
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
            using (Graphics g = CreateGraphics()) sc = Math.Max(1f, g.DpiX / 96f);
            ClientSize = new Size((int)(BW * sc), (int)(BH * sc));
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            bg = LoadImage("bg.jpg");
            fTitle = MakeFont("BarlowCondensed-ExtraBoldItalic.ttf", 34f, "Segoe UI Black");
            fBig = MakeFont("BarlowCondensed-ExtraBoldItalic.ttf", 44f, "Segoe UI Black");
            fBtn = MakeFont("BarlowCondensed-ExtraBoldItalic.ttf", 25f, "Segoe UI Black");
            fLbl = MakeFont("BarlowCondensed-Bold.ttf", 12.5f, "Segoe UI Semibold");
            fBody = MakeFont("Barlow-Medium.ttf", 13f, "Segoe UI");
            fSmall = MakeFont("Barlow-Medium.ttf", 11f, "Segoe UI");
            tip = new Random().Next(TIPS.Length);

            rBtn = new RectangleF(BW - 40 - 230, BH - 40 - 58, 230, 58);
            rClose = new RectangleF(BW - 44, 8, 36, 30);
            rMin = new RectangleF(BW - 82, 8, 36, 30);

            var t = new System.Windows.Forms.Timer { Interval = 33 };
            t.Tick += (s, e) => Tick();
            t.Start();

            var th = new Thread(Work) { IsBackground = true };
            th.Start();
        }

        protected override CreateParams CreateParams
        {
            get { var cp = base.CreateParams; cp.ClassStyle |= 0x20000; /* CS_DROPSHADOW */ cp.Style |= 0x20000; /* WS_MINIMIZEBOX: görev çubuğundan küçültme */ return cp; }
        }

        // ---------- kaynaklar ----------
        static Stream Res(string name)
        {
            return Assembly.GetExecutingAssembly().GetManifestResourceStream(name);
        }
        static Image LoadImage(string name)
        {
            try { using (var s = Res(name)) { var ms = new MemoryStream(); s.CopyTo(ms); return Image.FromStream(ms); } }
            catch { return null; }
        }
        static readonly List<PrivateFontCollection> pfcs = new List<PrivateFontCollection>();
        static Font MakeFont(string res, float px, string fallback)
        {
            if (Environment.GetEnvironmentVariable("SOKAK_FONTTEST") != null)
            {
                // yalnızca Linux/Mono önizlemesi: font sistemden
                string fam = res.StartsWith("BarlowCondensed-ExtraBold") ? "Barlow Condensed ExtraBold" : res.StartsWith("BarlowCondensed") ? "Barlow Condensed" : "Barlow Medium";
                FontStyle st = res.Contains("Italic") ? FontStyle.Italic : res.Contains("-Bold") ? FontStyle.Bold : FontStyle.Regular;
                return new Font(fam, px, st, GraphicsUnit.Pixel);
            }
            try
            {
                byte[] data;
                using (var s = Res(res)) { var ms = new MemoryStream(); s.CopyTo(ms); data = ms.ToArray(); }
                var pfc = new PrivateFontCollection();
                try
                {
                    string fd = Path.Combine(Path.GetTempPath(), "sokak_fontlar");
                    Directory.CreateDirectory(fd);
                    string fp = Path.Combine(fd, res);
                    if (!File.Exists(fp) || new FileInfo(fp).Length != data.Length) File.WriteAllBytes(fp, data);
                    pfc.AddFontFile(fp);
                }
                catch
                {
                    IntPtr p = Marshal.AllocCoTaskMem(data.Length);   // bilerek serbest bırakılmıyor (GDI+ gereği)
                    Marshal.Copy(data, 0, p, data.Length);
                    pfc.AddMemoryFont(p, data.Length);
                }
                if (pfc.Families.Length == 0) throw new Exception("font");
                pfcs.Add(pfc);
                FontFamily fam = pfc.Families[0];
                foreach (FontStyle st in new[] { FontStyle.Regular, FontStyle.Italic, FontStyle.Bold, FontStyle.Bold | FontStyle.Italic })
                    if (fam.IsStyleAvailable(st)) return new Font(fam, px, st, GraphicsUnit.Pixel);
            }
            catch { }
            return new Font(fallback, px * 0.8f, FontStyle.Regular, GraphicsUnit.Pixel);
        }

        // ---------- indirme ----------
        void Set(St s, string t, string sb) { state = s; title = t; sub = sb; }

        void Work()
        {
            string pck = Path.Combine(dir, "SOKAK.pck");
            string js = null;
            for (int i = 0; i < 3 && js == null; i++)
            {
                try { js = GetString(MANIFEST + "?t=" + DateTime.UtcNow.Ticks); }
                catch { Thread.Sleep(1200); }
            }
            if (js == null)
            {
                if (File.Exists(pck) && new FileInfo(pck).Length > 1000000)
                { Set(St.Ready, "OYUN HAZIR", "Sunucuya ulaşılamadı; mevcut sürümle oynayabilirsin."); return; }
                Fail("Sürüm bilgisi alınamadı. İnternet bağlantını kontrol edip tekrar dene."); return;
            }
            Match mv = Regex.Match(js, "\"version\"\\s*:\\s*\"([^\"]+)\"");
            Match mb = Regex.Match(js, "\"build\"\\s*:\\s*(\\d+)");
            Match ms = Regex.Match(js, "\"pck_size\"\\s*:\\s*(\\d+)");
            version = mv.Success ? mv.Groups[1].Value : "";
            string build = mb.Success ? mb.Groups[1].Value : "0";
            var parts = new List<Part>();
            foreach (Match m in Regex.Matches(js, "\"url\"\\s*:\\s*\"([^\"]+)\"\\s*,\\s*\"size\"\\s*:\\s*(\\d+)"))
                parts.Add(new Part { Url = m.Groups[1].Value, Size = long.Parse(m.Groups[2].Value) });
            long want = ms.Success ? long.Parse(ms.Groups[1].Value) : 0;
            if (parts.Count == 0) { Fail("Sürüm bilgisi okunamadı."); return; }
            if (want == 0) foreach (var p in parts) want += p.Size;

            if (File.Exists(pck) && new FileInfo(pck).Length == want)
            { Set(St.Ready, "OYUN HAZIR", "Oyun güncel. İyi oyunlar!"); return; }

            bool upd = File.Exists(pck);
            Set(St.Downloading, upd ? "GÜNCELLEME İNDİRİLİYOR" : "OYUN DOSYALARI İNDİRİLİYOR",
                "Lütfen bekleyin. Pencereyi kapatırsan indirme bir dahaki açılışta kaldığı yerden devam eder.");

            string tmp = Path.Combine(dir, "indirilenler");
            try
            {
                Directory.CreateDirectory(tmp);
                foreach (string f in Directory.GetFiles(tmp))           // başka sürümün yarım parçalarını sil
                    if (!Path.GetFileName(f).StartsWith("b" + build + "_")) File.Delete(f);
            }
            catch (Exception e) { Fail("Klasöre yazılamadı: " + e.Message); return; }

            Interlocked.Exchange(ref total, want);
            partCount = parts.Count;
            long before = 0;
            var files = new List<string>();
            for (int i = 0; i < parts.Count; i++)
            {
                string f = Path.Combine(tmp, "b" + build + "_parca" + i);
                files.Add(f);
                if (File.Exists(f)) before += Math.Min(new FileInfo(f).Length, parts[i].Size);
            }
            Interlocked.Exchange(ref done, before);
            lock (samples) samples.Clear();

            for (int i = 0; i < parts.Count; i++)
            {
                partIdx = i + 1;
                if (!DownloadPart(parts[i], files[i])) { if (!cancel) Fail("İndirme tamamlanamadı (parça " + (i + 1) + "). Bağlantını kontrol edip TEKRAR DENE'ye bas."); return; }
            }

            // birleştir
            Set(St.Merging, "DOSYALAR HAZIRLANIYOR", "İndirilen parçalar birleştiriliyor, az kaldı…");
            string outp = pck + ".new";
            try
            {
                Interlocked.Exchange(ref done, 0);
                using (var o = new FileStream(outp, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 20))
                {
                    var buf = new byte[1 << 20];
                    foreach (string f in files)
                        using (var s = new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20))
                        {
                            int n;
                            while ((n = s.Read(buf, 0, buf.Length)) > 0) { o.Write(buf, 0, n); Interlocked.Add(ref done, n); }
                        }
                }
                if (new FileInfo(outp).Length != want) { File.Delete(outp); Fail("Dosya boyutu tutmadı. TEKRAR DENE'ye bas."); return; }
                foreach (var p in Process.GetProcessesByName("SOKAK")) { try { p.Kill(); p.WaitForExit(3000); } catch { } }
                for (int k = 0; k < 10; k++)
                {
                    try { if (File.Exists(pck)) File.Delete(pck); File.Move(outp, pck); break; }
                    catch { if (k == 9) throw; Thread.Sleep(500); }
                }
                try { Directory.Delete(tmp, true); } catch { }
                try { File.WriteAllText(Path.Combine(dir, "surum.txt"), version + " (" + build + ")"); } catch { }
            }
            catch (Exception e) { Fail("Dosyalar yazılamadı: " + e.Message); return; }
            Set(St.Ready, "OYUN HAZIR", upd ? "Güncelleme tamamlandı. İyi oyunlar!" : "İndirme tamamlandı. İyi oyunlar!");
        }

        bool DownloadPart(Part p, string f)
        {
            var buf = new byte[1 << 16];
            for (int attempt = 0; attempt < 8 && !cancel; attempt++)
            {
                long have = File.Exists(f) ? new FileInfo(f).Length : 0;
                if (have == p.Size) return true;
                if (have > p.Size) { File.Delete(f); Interlocked.Add(ref done, -have); have = 0; }
                try
                {
                    var req = (HttpWebRequest)WebRequest.Create(p.Url);
                    req.UserAgent = "SOKAK-Baslatici/2.3";
                    req.Timeout = 30000; req.ReadWriteTimeout = 30000;
                    req.AutomaticDecompression = DecompressionMethods.None;
                    if (have > 0) req.AddRange(have);
                    using (var resp = (HttpWebResponse)req.GetResponse())
                    {
                        if (have > 0 && resp.StatusCode != HttpStatusCode.PartialContent)
                        { Interlocked.Add(ref done, -have); have = 0; }
                        using (var s = resp.GetResponseStream())
                        using (var o = new FileStream(f, have > 0 ? FileMode.Append : FileMode.Create, FileAccess.Write, FileShare.Read, 1 << 16))
                        {
                            int n;
                            while (!cancel && (n = s.Read(buf, 0, buf.Length)) > 0)
                            { o.Write(buf, 0, n); Interlocked.Add(ref done, n); }
                        }
                    }
                }
                catch { if (!cancel) Thread.Sleep(Math.Min(8000, 1000 * (attempt + 1))); }
            }
            return !cancel && File.Exists(f) && new FileInfo(f).Length == p.Size;
        }

        static string GetString(string url)
        {
            var req = (HttpWebRequest)WebRequest.Create(url);
            req.UserAgent = "SOKAK-Baslatici/2.3";
            req.Timeout = 15000;
            using (var resp = req.GetResponse())
            using (var r = new StreamReader(resp.GetResponseStream(), System.Text.Encoding.UTF8))
                return r.ReadToEnd();
        }

        void Fail(string msg) { err = msg; Set(St.Error, "İNDİRME BAŞARISIZ", msg); }

        void Retry()
        {
            if (state != St.Error) return;
            err = "";
            Set(St.Checking, "SÜRÜM KONTROL EDİLİYOR", "Sunucuya bağlanılıyor…");
            new Thread(Work) { IsBackground = true }.Start();
        }

        void Play()
        {
            try
            {
                Process.Start(new ProcessStartInfo(Path.Combine(dir, "SOKAK.exe")) { WorkingDirectory = dir, UseShellExecute = true });
                Close();
            }
            catch (Exception e) { Fail("Oyun başlatılamadı: " + e.Message); }
        }

        // ---------- animasyon ----------
        void Tick()
        {
            double now = clock.Elapsed.TotalSeconds;
            long d = Interlocked.Read(ref done);
            lock (samples)
            {
                samples.Enqueue(new KeyValuePair<double, long>(now, d));
                while (samples.Count > 2 && now - samples.Peek().Key > 4.0) samples.Dequeue();
                var first = samples.Peek();
                double dt = now - first.Key;
                if (dt > 0.5) speed = speed * 0.85 + 0.15 * Math.Max(0, (d - first.Value) / dt);
            }
            float target = state == St.Ready ? 1f : (float)Math.Min(1.0, (double)d / Math.Max(1, Interlocked.Read(ref total)));
            if (target < shown - 0.05f) shown = target; else shown += (target - shown) * 0.15f;
            tipT += 0.033;
            if (tipT > 6) { tipT = 0; tip = (tip + 1) % TIPS.Length; }
            Invalidate();
        }

        // ---------- çizim ----------
        protected override void OnPaint(PaintEventArgs e)
        {
            try { Paint2(e.Graphics); } catch { }
        }

        void Paint2(Graphics g)
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.TextRenderingHint = TextRenderingHint.AntiAlias;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.ScaleTransform(sc, sc);
            double t = clock.Elapsed.TotalSeconds;

            if (bg != null) g.DrawImage(bg, new RectangleF(0, 0, BW, BH));
            else g.Clear(BackColor);

            // pencere düğmeleri
            DrawWinBtn(g, rMin, "min");
            DrawWinBtn(g, rClose, "close");

            // durum etiketi
            string tag = state == St.Ready ? "HAZIR" : state == St.Error ? "HATA" : state == St.Merging ? "HAZIRLANIYOR" : state == St.Downloading ? "İNDİRİLİYOR" : "BAĞLANIYOR";
            Color tagC = state == St.Ready ? Color.FromArgb(74, 222, 128) : state == St.Error ? Color.FromArgb(255, 90, 70) : OR;
            float ty = 222;
            float pulse = (float)(0.55 + 0.45 * Math.Sin(t * 4));
            using (var b = new SolidBrush(Color.FromArgb((int)(255 * (state == St.Ready || state == St.Error ? 1 : pulse)), tagC)))
                g.FillEllipse(b, 42, ty + 4, 8, 8);
            using (var b = new SolidBrush(tagC)) DrawSpaced(g, tag, fLbl, b, 58, ty, 3.2f);
            if (version != "")
                using (var b = new SolidBrush(DIM)) DrawSpaced(g, "SÜRÜM " + version, fLbl, b, 58 + MeasureSpaced(g, tag, fLbl, 3.2f) + 18, ty, 3.2f);

            // başlık + açıklama
            using (var b = new SolidBrush(TX)) g.DrawString(title, fTitle, b, 38, ty + 18);
            using (var b = new SolidBrush(MUT)) g.DrawString(sub, fBody, b, new RectangleF(42, ty + 64, 560, 44));

            // ilerleme çubuğu
            float bx = 42, by = 352, bw = BW - 84, bh = 10;
            long dn = Interlocked.Read(ref done), tt = Interlocked.Read(ref total);
            bool showBar = state == St.Downloading || state == St.Merging || state == St.Ready;
            if (state == St.Checking) DrawIndeterminate(g, bx, by, bw, bh, t);
            else if (showBar || state == St.Error) DrawBar(g, bx, by, bw, bh, state == St.Error ? Math.Min(1f, (float)dn / Math.Max(1, tt)) : shown, t, state == St.Error);

            // yüzde
            if (state == St.Downloading || state == St.Merging)
            {
                string pc = ((int)Math.Floor(shown * 100)).ToString();
                SizeF s1 = g.MeasureString(pc, fBig);
                SizeF s2 = g.MeasureString("%", fBtn);
                float px = bx + bw - s1.Width - s2.Width + 14;
                using (var b = new SolidBrush(OR)) { g.DrawString("%", fBtn, b, px, by - 42); g.DrawString(pc, fBig, b, px + s2.Width - 8, by - 58); }
            }

            // alt bilgi satırı
            using (var b = new SolidBrush(MUT))
            {
                string info = "";
                if (state == St.Downloading)
                {
                    info = string.Format("{0:0} / {1:0} MB", dn / 1048576.0, tt / 1048576.0);
                    if (speed > 1000)
                    {
                        info += string.Format("   ·   {0:0.0} MB/sn", speed / 1048576.0);
                        double rem = (tt - dn) / speed;
                        info += "   ·   " + (rem >= 60 ? string.Format("~{0} dk {1} sn kaldı", (int)(rem / 60), (int)(rem % 60)) : string.Format("~{0} sn kaldı", (int)rem + 1));
                    }
                    info += "   ·   Parça " + partIdx + "/" + partCount;
                }
                else if (state == St.Merging) info = string.Format("{0:0} / {1:0} MB birleştirildi", dn / 1048576.0, tt / 1048576.0);
                else if (state == St.Ready) info = "Tüm dosyalar hazır";
                g.DrawString(info, fSmall, b, bx - 2, by + 19);
            }

            // ipucu
            float tipA = (float)Math.Min(1, Math.Min(tipT / 0.5, (6 - tipT) / 0.5));
            using (var b = new SolidBrush(Color.FromArgb((int)(255 * tipA), OR))) DrawSpaced(g, "İPUCU", fLbl, b, 42, BH - 80, 3f);
            using (var b = new SolidBrush(Color.FromArgb((int)(220 * tipA), TX)))
                g.DrawString(TIPS[tip], fSmall, b, new RectangleF(40, BH - 62, BW - 380, 40));

            // ana düğme
            DrawMainButton(g, t);
        }

        void DrawWinBtn(Graphics g, RectangleF r, string id)
        {
            bool h = hover == id;
            if (h) using (var b = new SolidBrush(id == "close" ? Color.FromArgb(200, 210, 50, 40) : Color.FromArgb(40, 255, 255, 255))) g.FillRectangle(b, r);
            using (var pen = new Pen(Color.FromArgb(h ? 255 : 170, TX), 1.6f))
            {
                float cx = r.X + r.Width / 2, cy = r.Y + r.Height / 2;
                if (id == "close") { g.DrawLine(pen, cx - 6, cy - 6, cx + 6, cy + 6); g.DrawLine(pen, cx + 6, cy - 6, cx - 6, cy + 6); }
                else g.DrawLine(pen, cx - 7, cy + 1, cx + 7, cy + 1);
            }
        }

        static GraphicsPath Skew(RectangleF r, float cut)
        {
            var p = new GraphicsPath();
            p.AddPolygon(new[] { new PointF(r.X + cut, r.Y), new PointF(r.Right, r.Y), new PointF(r.Right - cut, r.Bottom), new PointF(r.X, r.Bottom) });
            return p;
        }

        void DrawBar(Graphics g, float x, float y, float w, float h, float f, double t, bool bad)
        {
            using (var track = Skew(new RectangleF(x, y, w, h), 6))
            using (var b = new SolidBrush(Color.FromArgb(200, 37, 43, 51))) g.FillPath(b, track);
            float fw = Math.Max(0, Math.Min(1, f)) * w;
            if (fw < 2) return;
            var fr = new RectangleF(x, y, fw, h);
            using (var path = Skew(fr, 6))
            {
                Color a = bad ? Color.FromArgb(150, 40, 30) : ORD, c = bad ? Color.FromArgb(255, 90, 70) : OR2;
                using (var lg = new LinearGradientBrush(new RectangleF(x - 1, y, fw + 2, h), a, c, 0f)) g.FillPath(lg, path);
                if (!bad)
                {
                    // hareketli parıltı
                    float sx = x + (float)((t * 260) % (w + 240)) - 120;
                    var gs = g.Save();
                    g.SetClip(path);
                    using (var sh = new LinearGradientBrush(new RectangleF(sx, y, 120, h), Color.FromArgb(0, 255, 255, 255), Color.FromArgb(0, 255, 255, 255), 0f))
                    {
                        var cb = new ColorBlend(3);
                        cb.Colors = new[] { Color.FromArgb(0, 255, 255, 255), Color.FromArgb(150, 255, 240, 220), Color.FromArgb(0, 255, 255, 255) };
                        cb.Positions = new[] { 0f, 0.5f, 1f };
                        sh.InterpolationColors = cb;
                        g.FillRectangle(sh, sx, y, 120, h);
                    }
                    g.Restore(gs);
                }
            }
            if (!bad)
            {
                // uçta parlama
                float ex = x + fw;
                using (var gp = new GraphicsPath())
                {
                    gp.AddEllipse(ex - 26, y - 14, 52, h + 28);
                    using (var pg = new PathGradientBrush(gp) { CenterColor = Color.FromArgb(120, 255, 170, 80), SurroundColors = new[] { Color.FromArgb(0, 255, 138, 31) } })
                        g.FillPath(pg, gp);
                }
            }
        }

        void DrawIndeterminate(Graphics g, float x, float y, float w, float h, double t)
        {
            using (var track = Skew(new RectangleF(x, y, w, h), 6))
            using (var b = new SolidBrush(Color.FromArgb(200, 37, 43, 51))) g.FillPath(b, track);
            float seg = w * 0.22f;
            float sx = x + (float)(((Math.Sin(t * 2.2) + 1) / 2) * (w - seg));
            using (var path = Skew(new RectangleF(sx, y, seg, h), 6))
            using (var lg = new LinearGradientBrush(new RectangleF(sx - 1, y, seg + 2, h), ORD, OR2, 0f)) g.FillPath(lg, path);
        }

        void DrawMainButton(Graphics g, double t)
        {
            bool ready = state == St.Ready, error = state == St.Error;
            bool active = ready || error;
            bool h = hover == "btn" && active;
            RectangleF r = rBtn;
            if (h) r.Offset(0, -2);
            string label = ready ? "BAŞLAT" : error ? "TEKRAR DENE" : state == St.Merging ? "HAZIRLANIYOR" : state == St.Checking ? "BEKLEYİN" : "İNDİRİLİYOR";

            if (ready)
            {
                // nabız gibi atan parlama
                float p = (float)(0.5 + 0.5 * Math.Sin(t * 3));
                for (int i = 3; i >= 1; i--)
                {
                    var gr = RectangleF.Inflate(r, i * 5 + p * 4, i * 4 + p * 3);
                    using (var gp = Skew(gr, 18))
                    using (var b = new SolidBrush(Color.FromArgb((int)(22 + p * 18), OR))) g.FillPath(b, gp);
                }
            }
            using (var path = Skew(r, 16))
            {
                if (active)
                {
                    Color top = error ? Color.FromArgb(90, 98, 110) : OR2, bot = error ? Color.FromArgb(55, 62, 72) : ORD;
                    if (h) { top = ControlPaint.Light(top, 0.25f); }
                    using (var lg = new LinearGradientBrush(r, top, bot, 90f))
                    {
                        if (!error)
                        {
                            var cb = new ColorBlend(3);
                            cb.Colors = new[] { h ? Color.FromArgb(255, 205, 140) : OR2, OR, ORD };
                            cb.Positions = new[] { 0f, 0.45f, 1f };
                            lg.InterpolationColors = cb;
                        }
                        g.FillPath(lg, path);
                    }
                }
                else
                {
                    using (var b = new SolidBrush(Color.FromArgb(220, 30, 35, 42))) g.FillPath(b, path);
                    using (var pen = new Pen(Color.FromArgb(70, 255, 255, 255), 1f)) g.DrawPath(pen, path);
                }
            }
            Color tc = ready ? Color.FromArgb(26, 15, 4) : error ? TX : DIM;
            using (var b = new SolidBrush(tc))
            {
                float sp = 2.2f;
                float tw = MeasureSpaced(g, label, fBtn, sp);
                float lx = r.X + (r.Width - tw) / 2;
                if (ready)
                {
                    // oynat üçgeni
                    float ix = lx - 14, iy = r.Y + r.Height / 2;
                    g.FillPolygon(b, new[] { new PointF(ix - 7, iy - 9), new PointF(ix + 7, iy), new PointF(ix - 7, iy + 9) });
                    lx += 10;
                }
                DrawSpaced(g, label, fBtn, b, lx, r.Y + (r.Height - fBtn.Size * 1.2f) / 2 - 1, sp);
            }
        }

        static float MeasureSpaced(Graphics g, string s, Font f, float sp)
        {
            float w = 0;
            var fmt = StringFormat.GenericTypographic;
            foreach (char c in s) w += (c == ' ' ? f.Size * 0.28f : g.MeasureString(c.ToString(), f, 1000, fmt).Width) + sp;
            return w - sp;
        }
        static void DrawSpaced(Graphics g, string s, Font f, Brush b, float x, float y, float sp)
        {
            var fmt = StringFormat.GenericTypographic;
            foreach (char c in s)
            {
                if (c == ' ') { x += f.Size * 0.28f + sp; continue; }
                g.DrawString(c.ToString(), f, b, x, y, fmt);
                x += g.MeasureString(c.ToString(), f, 1000, fmt).Width + sp;
            }
        }

        // ---------- fare ----------
        string HitTest(Point p)
        {
            var q = new PointF(p.X / sc, p.Y / sc);
            if (rClose.Contains(q)) return "close";
            if (rMin.Contains(q)) return "min";
            if (rBtn.Contains(q)) return "btn";
            return "";
        }
        protected override void OnMouseMove(MouseEventArgs e)
        {
            if (dragging) { Location = new Point(Location.X + e.X - dragFrom.X, Location.Y + e.Y - dragFrom.Y); return; }
            hover = HitTest(e.Location);
            bool hand = hover == "close" || hover == "min" || (hover == "btn" && (state == St.Ready || state == St.Error));
            Cursor = hand ? Cursors.Hand : Cursors.Default;
        }
        protected override void OnMouseLeave(EventArgs e) { hover = ""; }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            if (e.Button == MouseButtons.Left && HitTest(e.Location) == "") { dragging = true; dragFrom = e.Location; }
        }
        protected override void OnMouseUp(MouseEventArgs e)
        {
            if (dragging) { dragging = false; return; }
            if (e.Button != MouseButtons.Left) return;
            string h = HitTest(e.Location);
            if (h == "close") Close();
            else if (h == "min") WindowState = FormWindowState.Minimized;
            else if (h == "btn") { if (state == St.Ready) Play(); else if (state == St.Error) Retry(); }
        }
        protected override void OnKeyDown(KeyEventArgs e)
        {
            if (e.KeyCode == Keys.Enter && state == St.Ready) Play();
            if (e.KeyCode == Keys.Escape) Close();
        }
        protected override void OnFormClosing(FormClosingEventArgs e) { cancel = true; base.OnFormClosing(e); }
    }
}
