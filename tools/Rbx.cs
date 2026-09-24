// Roblox binary place (.rbxl) reader/writer. C# 5 compatible.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

public class RProp
{
    public string Name;
    public byte Type;
    public object Value;
    public RProp(string n, byte t, object v) { Name = n; Type = t; Value = v; }
}

public class RInst
{
    public int Ref = -1;
    public string ClassName;
    public bool IsService;
    public RInst Parent;
    public List<RInst> Children = new List<RInst>();
    public List<RProp> Props = new List<RProp>();

    public RProp GetProp(string name)
    {
        foreach (var p in Props) if (p.Name == name) return p;
        return null;
    }
    public string Name
    {
        get { var p = GetProp("Name"); return p == null ? "" : Encoding.UTF8.GetString((byte[])p.Value); }
    }
    public void SetParent(RInst parent)
    {
        if (Parent != null) Parent.Children.Remove(this);
        Parent = parent;
        if (parent != null) parent.Children.Add(this);
    }
    public RInst Find(string name)
    {
        foreach (var c in Children) if (c.Name == name) return c;
        return null;
    }
    public string Path()
    {
        return Parent == null ? Name : Parent.Path() + "." + Name;
    }
}

// value types
public class UDimV { public float S; public int O; }
public class UDim2V { public float XS, YS; public int XO, YO; }
public class CFrameV { public byte Id; public float[] R = new float[9]; public float[] P = new float[3]; }
public class PhysV { public byte Flag; public float[] Vals; }
public class OptCFrameV { public CFrameV CF; public bool Has; }
public class FontV { public byte[] Family; public ushort Weight; public byte Style; public byte[] CachedFaceId; }
public class RawV { public byte[] Data; } // for types we just carry through
public class ContentV { public int Kind; public byte[] Uri; public RInst Obj; }

public class RChunk { public string Name; public byte[] Data; public byte[] Header; }

public class RbxFile
{
    public List<RInst> Instances = new List<RInst>(); // file (PRNT) order
    public List<KeyValuePair<string, string>> Meta = new List<KeyValuePair<string, string>>();
    public bool HadMeta;
    public List<byte[]> SharedStrings = new List<byte[]>();
    public List<byte[]> SharedHashes = new List<byte[]>();
    public Dictionary<string, List<RInst>> ClassOrder = new Dictionary<string, List<RInst>>();
    public Dictionary<string, List<KeyValuePair<string, byte>>> ClassProps = new Dictionary<string, List<KeyValuePair<string, byte>>>();
    public List<string> ClassNames = new List<string>(); // original class id order
    public Dictionary<string, byte[]> OriginalChunks = new Dictionary<string, byte[]>(); // key -> decompressed payload

    public IEnumerable<RInst> Roots { get { return Instances.Where(i => i.Parent == null); } }

    // ---------------- low-level helpers ----------------
    static int ReadI32(byte[] d, ref int p) { int v = BitConverter.ToInt32(d, p); p += 4; return v; }
    static uint ReadU32(byte[] d, ref int p) { uint v = BitConverter.ToUInt32(d, p); p += 4; return v; }
    static float ReadF32(byte[] d, ref int p) { float v = BitConverter.ToSingle(d, p); p += 4; return v; }
    static byte[] ReadStr(byte[] d, ref int p)
    {
        int len = ReadI32(d, ref p);
        var b = new byte[len];
        Array.Copy(d, p, b, 0, len);
        p += len;
        return b;
    }

    static byte[][] Deinterleave(byte[] d, ref int p, int count, int width)
    {
        var res = new byte[count][];
        for (int i = 0; i < count; i++) res[i] = new byte[width];
        for (int b = 0; b < width; b++)
            for (int i = 0; i < count; i++)
                res[i][b] = d[p + b * count + i];
        p += count * width;
        return res;
    }

    static uint BE32(byte[] b) { return ((uint)b[0] << 24) | ((uint)b[1] << 16) | ((uint)b[2] << 8) | b[3]; }
    static ulong BE64(byte[] b) { ulong v = 0; for (int i = 0; i < 8; i++) v = (v << 8) | b[i]; return v; }
    static int UnZig32(uint n) { return (int)(n >> 1) ^ -(int)(n & 1); }
    static long UnZig64(ulong n) { return (long)(n >> 1) ^ -(long)(n & 1); }
    static float RbxFloat(uint n) { uint bits = (n >> 1) | (n << 31); return BitConverter.ToSingle(BitConverter.GetBytes(bits), 0); }

    static int[] ReadInts(byte[] d, ref int p, int count)
    {
        var raw = Deinterleave(d, ref p, count, 4);
        var r = new int[count];
        for (int i = 0; i < count; i++) r[i] = UnZig32(BE32(raw[i]));
        return r;
    }
    static uint[] ReadU32s(byte[] d, ref int p, int count)
    {
        var raw = Deinterleave(d, ref p, count, 4);
        var r = new uint[count];
        for (int i = 0; i < count; i++) r[i] = BE32(raw[i]);
        return r;
    }
    static float[] ReadFloats(byte[] d, ref int p, int count)
    {
        var raw = Deinterleave(d, ref p, count, 4);
        var r = new float[count];
        for (int i = 0; i < count; i++) r[i] = RbxFloat(BE32(raw[i]));
        return r;
    }
    static int[] ReadRefs(byte[] d, ref int p, int count)
    {
        var r = ReadInts(d, ref p, count);
        for (int i = 1; i < count; i++) r[i] += r[i - 1];
        return r;
    }

    static byte[] Lz4Decompress(byte[] src, int unc)
    {
        var o = new byte[unc];
        int ip = 0, op = 0;
        while (ip < src.Length)
        {
            int token = src[ip++];
            int lit = token >> 4;
            if (lit == 15) { int b; do { b = src[ip++]; lit += b; } while (b == 255); }
            Array.Copy(src, ip, o, op, lit); ip += lit; op += lit;
            if (ip >= src.Length) break;
            int off = src[ip] | (src[ip + 1] << 8); ip += 2;
            int ml = token & 15;
            if (ml == 15) { int b; do { b = src[ip++]; ml += b; } while (b == 255); }
            ml += 4;
            for (int i = 0; i < ml; i++) { o[op] = o[op - off]; op++; }
        }
        return o;
    }

    // ---------------- reading ----------------
    public static RbxFile Load(string path)
    {
        var d = File.ReadAllBytes(path);
        var f = new RbxFile();
        string magic = Encoding.ASCII.GetString(d, 0, 8);
        if (magic != "<roblox!") throw new Exception("not a binary roblox file");
        int p = 16;
        int classCount = ReadI32(d, ref p);
        int instCount = ReadI32(d, ref p);
        p = 32;
        var byRef = new Dictionary<int, RInst>();
        var classById = new Dictionary<int, string>();
        var classInsts = new Dictionary<int, List<RInst>>();
        var pendingRefs = new List<Tuple<RProp, int>>();
        var pendingContent = new List<Tuple<ContentV, int>>();
        int chunkIndex = 0;
        while (p < d.Length)
        {
            string name = Encoding.ASCII.GetString(d, p, 4).TrimEnd('\0');
            int comp = BitConverter.ToInt32(d, p + 4);
            int unc = BitConverter.ToInt32(d, p + 8);
            p += 16;
            byte[] data;
            if (comp == 0) { data = new byte[unc]; Array.Copy(d, p, data, 0, unc); p += unc; }
            else
            {
                var cd = new byte[comp]; Array.Copy(d, p, cd, 0, comp); p += comp;
                if (comp >= 4 && cd[0] == 0x28 && cd[1] == 0xB5 && cd[2] == 0x2F && cd[3] == 0xFD) data = Zstd.Decompress(cd);
                else data = Lz4Decompress(cd, unc);
                if (data.Length != unc) throw new Exception("chunk size mismatch in " + name);
            }
            int q = 0;
            if (name == "META")
            {
                f.HadMeta = true;
                int n = ReadI32(data, ref q);
                for (int i = 0; i < n; i++)
                {
                    string k = Encoding.UTF8.GetString(ReadStr(data, ref q));
                    string v = Encoding.UTF8.GetString(ReadStr(data, ref q));
                    f.Meta.Add(new KeyValuePair<string, string>(k, v));
                }
                f.OriginalChunks["META"] = data;
            }
            else if (name == "SSTR")
            {
                ReadI32(data, ref q);
                int n = ReadI32(data, ref q);
                for (int i = 0; i < n; i++)
                {
                    var h = new byte[16]; Array.Copy(data, q, h, 0, 16); q += 16;
                    f.SharedHashes.Add(h);
                    f.SharedStrings.Add(ReadStr(data, ref q));
                }
                f.OriginalChunks["SSTR"] = data;
            }
            else if (name == "INST")
            {
                int cid = ReadI32(data, ref q);
                string cname = Encoding.UTF8.GetString(ReadStr(data, ref q));
                byte fmt = data[q++];
                int n = ReadI32(data, ref q);
                var refs = ReadRefs(data, ref q, n);
                var list = new List<RInst>();
                foreach (var r in refs)
                {
                    var inst = new RInst { Ref = r, ClassName = cname, IsService = fmt == 1 };
                    byRef[r] = inst;
                    list.Add(inst);
                }
                classById[cid] = cname;
                classInsts[cid] = list;
                f.ClassNames.Add(cname);
                f.ClassOrder[cname] = list;
                f.ClassProps[cname] = new List<KeyValuePair<string, byte>>();
                f.OriginalChunks["INST:" + cname] = data;
            }
            else if (name == "PROP")
            {
                int cid = ReadI32(data, ref q);
                string pname = Encoding.UTF8.GetString(ReadStr(data, ref q));
                byte type = data[q++];
                var insts = classInsts[cid];
                string cname = classById[cid];
                f.ClassProps[cname].Add(new KeyValuePair<string, byte>(pname, type));
                f.OriginalChunks["PROP:" + cname + ":" + pname] = data;
                object[] vals;
                try { vals = ReadValues(data, ref q, type, insts.Count, pendingContent); }
                catch (Exception e)
                {
                    int start = 4 + 4 + Encoding.UTF8.GetByteCount(pname) + 1;
                    throw new Exception("PROP " + cname + "." + pname + " type 0x" + type.ToString("X2") + " n=" + insts.Count + " len=" + data.Length +
                        " payload=" + BitConverter.ToString(data.Skip(start).Take(96).ToArray()), e);
                }
                if (q != data.Length) throw new Exception("PROP " + cname + "." + pname + " type " + type + " left " + (data.Length - q) + " bytes");
                for (int i = 0; i < insts.Count; i++)
                {
                    var prop = new RProp(pname, type, vals[i]);
                    if (type == 0x13) { pendingRefs.Add(Tuple.Create(prop, (int)vals[i])); prop.Value = null; }
                    insts[i].Props.Add(prop);
                }
            }
            else if (name == "PRNT")
            {
                q = 1;
                int n = ReadI32(data, ref q);
                var kids = ReadRefs(data, ref q, n);
                var parents = ReadRefs(data, ref q, n);
                for (int i = 0; i < n; i++)
                {
                    var c = byRef[kids[i]];
                    f.Instances.Add(c);
                    if (parents[i] >= 0) c.SetParent(byRef[parents[i]]);
                }
                f.OriginalChunks["PRNT"] = data;
            }
            else if (name == "END") break;
            else throw new Exception("unknown chunk " + name);
            chunkIndex++;
        }
        foreach (var pr in pendingRefs)
        {
            RInst target;
            pr.Item1.Value = (pr.Item2 >= 0 && byRef.TryGetValue(pr.Item2, out target)) ? target : null;
        }
        foreach (var pc in pendingContent)
        {
            RInst target;
            pc.Item1.Obj = (pc.Item2 >= 0 && byRef.TryGetValue(pc.Item2, out target)) ? target : null;
        }
        // instances missing from PRNT (shouldn't happen) get appended
        foreach (var kv in byRef) if (!f.Instances.Contains(kv.Value)) f.Instances.Add(kv.Value);
        if (f.Instances.Count != instCount) Console.Error.WriteLine("warning: header instance count " + instCount + " vs " + f.Instances.Count);
        if (f.ClassNames.Count != classCount) Console.Error.WriteLine("warning: header class count mismatch");
        return f;
    }

    static CFrameV[] ReadCFrames(byte[] d, ref int p, int n)
    {
        var res = new CFrameV[n];
        for (int i = 0; i < n; i++)
        {
            var cf = new CFrameV();
            cf.Id = d[p++];
            if (cf.Id == 0) { for (int k = 0; k < 9; k++) cf.R[k] = ReadF32(d, ref p); }
            else cf.R = SpecialRotation(cf.Id);
            res[i] = cf;
        }
        var x = ReadFloats(d, ref p, n);
        var y = ReadFloats(d, ref p, n);
        var z = ReadFloats(d, ref p, n);
        for (int i = 0; i < n; i++) { res[i].P[0] = x[i]; res[i].P[1] = y[i]; res[i].P[2] = z[i]; }
        return res;
    }

    static readonly float[][] Basis = {
        new float[]{1,0,0}, new float[]{0,1,0}, new float[]{0,0,1},
        new float[]{-1,0,0}, new float[]{0,-1,0}, new float[]{0,0,-1}
    };

    public static float[] SpecialRotation(byte id)
    {
        int n = id - 1;
        int xi = n / 6, yi = n % 6;
        var r0 = Basis[xi];
        var r1 = Basis[yi];
        // row-major: first row = R00 R01 R02 = X vector components? Roblox: special id encodes rightVector(x) and upVector(y) of the *columns*.
        var zc = new float[] { r0[1] * r1[2] - r0[2] * r1[1], r0[2] * r1[0] - r0[0] * r1[2], r0[0] * r1[1] - r0[1] * r1[0] };
        // matrix columns: X = r0, Y = r1, Z = zc -> row-major R[row*3+col]
        return new float[] { r0[0], r1[0], zc[0], r0[1], r1[1], zc[1], r0[2], r1[2], zc[2] };
    }

    static object[] ReadValues(byte[] d, ref int p, byte type, int n, List<Tuple<ContentV, int>> pendingContent)
    {
        var vals = new object[n];
        switch (type)
        {
            case 0x01: for (int i = 0; i < n; i++) vals[i] = ReadStr(d, ref p); break;
            case 0x02: for (int i = 0; i < n; i++) vals[i] = d[p++] != 0; break;
            case 0x03: { var a = ReadInts(d, ref p, n); for (int i = 0; i < n; i++) vals[i] = a[i]; } break;
            case 0x04: { var a = ReadFloats(d, ref p, n); for (int i = 0; i < n; i++) vals[i] = a[i]; } break;
            case 0x05: for (int i = 0; i < n; i++) { vals[i] = BitConverter.ToDouble(d, p); p += 8; } break;
            case 0x06:
                {
                    var s = ReadFloats(d, ref p, n); var o = ReadInts(d, ref p, n);
                    for (int i = 0; i < n; i++) vals[i] = new UDimV { S = s[i], O = o[i] };
                }
                break;
            case 0x07:
                {
                    var xs = ReadFloats(d, ref p, n); var ys = ReadFloats(d, ref p, n);
                    var xo = ReadInts(d, ref p, n); var yo = ReadInts(d, ref p, n);
                    for (int i = 0; i < n; i++) vals[i] = new UDim2V { XS = xs[i], YS = ys[i], XO = xo[i], YO = yo[i] };
                }
                break;
            case 0x08: for (int i = 0; i < n; i++) { var a = new float[6]; for (int k = 0; k < 6; k++) a[k] = ReadF32(d, ref p); vals[i] = a; } break;
            case 0x09:
            case 0x0A: for (int i = 0; i < n; i++) vals[i] = d[p++]; break;
            case 0x0B:
            case 0x12:
            case 0x1C: { var a = ReadU32s(d, ref p, n); for (int i = 0; i < n; i++) vals[i] = a[i]; } break;
            case 0x0C:
                {
                    var r = ReadFloats(d, ref p, n); var g = ReadFloats(d, ref p, n); var b = ReadFloats(d, ref p, n);
                    for (int i = 0; i < n; i++) vals[i] = new float[] { r[i], g[i], b[i] };
                }
                break;
            case 0x0D:
                {
                    var x = ReadFloats(d, ref p, n); var y = ReadFloats(d, ref p, n);
                    for (int i = 0; i < n; i++) vals[i] = new float[] { x[i], y[i] };
                }
                break;
            case 0x0E:
                {
                    var x = ReadFloats(d, ref p, n); var y = ReadFloats(d, ref p, n); var z = ReadFloats(d, ref p, n);
                    for (int i = 0; i < n; i++) vals[i] = new float[] { x[i], y[i], z[i] };
                }
                break;
            case 0x10: { var a = ReadCFrames(d, ref p, n); for (int i = 0; i < n; i++) vals[i] = a[i]; } break;
            case 0x13: { var a = ReadRefs(d, ref p, n); for (int i = 0; i < n; i++) vals[i] = a[i]; } break;
            case 0x14: for (int i = 0; i < n; i++) { vals[i] = new short[] { BitConverter.ToInt16(d, p), BitConverter.ToInt16(d, p + 2), BitConverter.ToInt16(d, p + 4) }; p += 6; } break;
            case 0x15:
                for (int i = 0; i < n; i++)
                {
                    int k = ReadI32(d, ref p); var a = new float[k * 3];
                    for (int j = 0; j < k * 3; j++) a[j] = ReadF32(d, ref p);
                    vals[i] = a;
                }
                break;
            case 0x16:
                for (int i = 0; i < n; i++)
                {
                    int k = ReadI32(d, ref p); var a = new float[k * 5];
                    for (int j = 0; j < k * 5; j++) a[j] = ReadF32(d, ref p);
                    vals[i] = a;
                }
                break;
            case 0x17: for (int i = 0; i < n; i++) { vals[i] = new float[] { ReadF32(d, ref p), ReadF32(d, ref p) }; } break;
            case 0x18:
                {
                    var a = ReadFloats(d, ref p, n); var b = ReadFloats(d, ref p, n); var c = ReadFloats(d, ref p, n); var e = ReadFloats(d, ref p, n);
                    for (int i = 0; i < n; i++) vals[i] = new float[] { a[i], b[i], c[i], e[i] };
                }
                break;
            case 0x19:
                for (int i = 0; i < n; i++)
                {
                    var pv = new PhysV { Flag = d[p++] };
                    // bit0 = custom values present, bit1 = newer format with AcousticAbsorption (extra float when custom)
                    int cnt = (pv.Flag & 1) != 0 ? (5 + ((pv.Flag & 2) != 0 ? 1 : 0)) : 0;
                    pv.Vals = new float[cnt];
                    for (int k = 0; k < cnt; k++) pv.Vals[k] = ReadF32(d, ref p);
                    vals[i] = pv;
                }
                break;
            case 0x1A:
                {
                    var r = new byte[n]; var g = new byte[n]; var b = new byte[n];
                    Array.Copy(d, p, r, 0, n); p += n; Array.Copy(d, p, g, 0, n); p += n; Array.Copy(d, p, b, 0, n); p += n;
                    for (int i = 0; i < n; i++) vals[i] = new byte[] { r[i], g[i], b[i] };
                }
                break;
            case 0x1B:
                {
                    var raw = Deinterleave(d, ref p, n, 8);
                    for (int i = 0; i < n; i++) vals[i] = UnZig64(BE64(raw[i]));
                }
                break;
            case 0x1E:
                {
                    if (d[p++] != 0x10) throw new Exception("OptionalCFrame: expected CFrame");
                    var cfs = ReadCFrames(d, ref p, n);
                    if (d[p++] != 0x02) throw new Exception("OptionalCFrame: expected Bool");
                    for (int i = 0; i < n; i++) vals[i] = new OptCFrameV { CF = cfs[i], Has = d[p++] != 0 };
                }
                break;
            case 0x1F:
            case 0x21:
                {
                    int w = type == 0x1F ? 16 : 8;
                    var raw = Deinterleave(d, ref p, n, w);
                    for (int i = 0; i < n; i++) vals[i] = new RawV { Data = raw[i] };
                }
                break;
            case 0x20:
                for (int i = 0; i < n; i++)
                {
                    var fv = new FontV();
                    fv.Family = ReadStr(d, ref p);
                    fv.Weight = BitConverter.ToUInt16(d, p); p += 2;
                    fv.Style = d[p++];
                    fv.CachedFaceId = ReadStr(d, ref p);
                    vals[i] = fv;
                }
                break;
            case 0x22:
                {
                    // Content: source-type array, then URIs, then object referents, then external objects
                    var kinds = ReadInts(d, ref p, n);
                    int uriCount = ReadI32(d, ref p);
                    var uris = new byte[uriCount][];
                    for (int i = 0; i < uriCount; i++) uris[i] = ReadStr(d, ref p);
                    int objCount = ReadI32(d, ref p);
                    var objs = ReadRefs(d, ref p, objCount);
                    int extCount = ReadI32(d, ref p);
                    if (extCount != 0) throw new Exception("Content: external objects not supported");
                    int ui = 0, oi = 0;
                    for (int i = 0; i < n; i++)
                    {
                        var cv = new ContentV { Kind = kinds[i] };
                        if (cv.Kind == 1) cv.Uri = uris[ui++];
                        else if (cv.Kind == 2) pendingContent.Add(Tuple.Create(cv, objs[oi++]));
                        vals[i] = cv;
                    }
                }
                break;
            default:
                throw new Exception("unsupported property type 0x" + type.ToString("X2"));
        }
        return vals;
    }

    // ---------------- writing ----------------
    class W
    {
        public MemoryStream S = new MemoryStream();
        public void B(byte b) { S.WriteByte(b); }
        public void Bytes(byte[] b) { S.Write(b, 0, b.Length); }
        public void I32(int v) { Bytes(BitConverter.GetBytes(v)); }
        public void F32(float v) { Bytes(BitConverter.GetBytes(v)); }
        public void Str(byte[] b) { I32(b.Length); Bytes(b); }
        public void Str(string s) { Str(Encoding.UTF8.GetBytes(s)); }
        public void Interleave(byte[][] vals, int width)
        {
            for (int b = 0; b < width; b++)
                foreach (var v in vals) S.WriteByte(v[b]);
        }
        public byte[] ToArray() { return S.ToArray(); }
    }

    static byte[] BEb32(uint v) { return new byte[] { (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v }; }
    static byte[] BEb64(ulong v) { var b = new byte[8]; for (int i = 7; i >= 0; i--) { b[i] = (byte)v; v >>= 8; } return b; }
    static uint Zig32(int v) { return (uint)((v << 1) ^ (v >> 31)); }
    static ulong Zig64(long v) { return (ulong)((v << 1) ^ (v >> 63)); }
    static uint FloatBits(float f) { uint bits = BitConverter.ToUInt32(BitConverter.GetBytes(f), 0); return (bits << 1) | (bits >> 31); }

    static void WInts(W w, IList<int> vals) { w.Interleave(vals.Select(v => BEb32(Zig32(v))).ToArray(), 4); }
    static void WU32s(W w, IList<uint> vals) { w.Interleave(vals.Select(v => BEb32(v)).ToArray(), 4); }
    static void WFloats(W w, IList<float> vals) { w.Interleave(vals.Select(v => BEb32(FloatBits(v))).ToArray(), 4); }
    static void WRefs(W w, IList<int> refs)
    {
        var deltas = new int[refs.Count];
        int prev = 0;
        for (int i = 0; i < refs.Count; i++) { deltas[i] = refs[i] - prev; prev = refs[i]; }
        WInts(w, deltas);
    }

    static void WCFrames(W w, IList<CFrameV> cfs)
    {
        foreach (var cf in cfs)
        {
            w.B(cf.Id);
            if (cf.Id == 0) foreach (var r in cf.R) w.F32(r);
        }
        WFloats(w, cfs.Select(c => c.P[0]).ToList());
        WFloats(w, cfs.Select(c => c.P[1]).ToList());
        WFloats(w, cfs.Select(c => c.P[2]).ToList());
    }

    static int RefOf(object v) { var i = v as RInst; return i == null ? -1 : i.Ref; }

    static void WriteValues(W w, byte type, List<object> vals)
    {
        int n = vals.Count;
        switch (type)
        {
            case 0x01: foreach (var v in vals) w.Str((byte[])v); break;
            case 0x02: foreach (var v in vals) w.B((bool)v ? (byte)1 : (byte)0); break;
            case 0x03: WInts(w, vals.Select(v => (int)v).ToList()); break;
            case 0x04: WFloats(w, vals.Select(v => (float)v).ToList()); break;
            case 0x05: foreach (var v in vals) w.Bytes(BitConverter.GetBytes((double)v)); break;
            case 0x06:
                WFloats(w, vals.Select(v => ((UDimV)v).S).ToList());
                WInts(w, vals.Select(v => ((UDimV)v).O).ToList());
                break;
            case 0x07:
                WFloats(w, vals.Select(v => ((UDim2V)v).XS).ToList());
                WFloats(w, vals.Select(v => ((UDim2V)v).YS).ToList());
                WInts(w, vals.Select(v => ((UDim2V)v).XO).ToList());
                WInts(w, vals.Select(v => ((UDim2V)v).YO).ToList());
                break;
            case 0x08: foreach (var v in vals) foreach (var f in (float[])v) w.F32(f); break;
            case 0x09:
            case 0x0A: foreach (var v in vals) w.B((byte)v); break;
            case 0x0B:
            case 0x12:
            case 0x1C: WU32s(w, vals.Select(v => (uint)v).ToList()); break;
            case 0x0C:
            case 0x0E:
                for (int k = 0; k < 3; k++) { int kk = k; WFloats(w, vals.Select(v => ((float[])v)[kk]).ToList()); }
                break;
            case 0x0D:
                for (int k = 0; k < 2; k++) { int kk = k; WFloats(w, vals.Select(v => ((float[])v)[kk]).ToList()); }
                break;
            case 0x10: WCFrames(w, vals.Select(v => (CFrameV)v).ToList()); break;
            case 0x13: WRefs(w, vals.Select(v => RefOf(v)).ToList()); break;
            case 0x14: foreach (var v in vals) foreach (var s in (short[])v) w.Bytes(BitConverter.GetBytes(s)); break;
            case 0x15: foreach (var v in vals) { var a = (float[])v; w.I32(a.Length / 3); foreach (var f in a) w.F32(f); } break;
            case 0x16: foreach (var v in vals) { var a = (float[])v; w.I32(a.Length / 5); foreach (var f in a) w.F32(f); } break;
            case 0x17: foreach (var v in vals) foreach (var f in (float[])v) w.F32(f); break;
            case 0x18:
                for (int k = 0; k < 4; k++) { int kk = k; WFloats(w, vals.Select(v => ((float[])v)[kk]).ToList()); }
                break;
            case 0x19: foreach (var v in vals) { var pv = (PhysV)v; w.B(pv.Flag); foreach (var f in pv.Vals) w.F32(f); } break;
            case 0x1A:
                for (int k = 0; k < 3; k++) foreach (var v in vals) w.B(((byte[])v)[k]);
                break;
            case 0x1B: w.Interleave(vals.Select(v => BEb64(Zig64((long)v))).ToArray(), 8); break;
            case 0x1E:
                w.B(0x10);
                WCFrames(w, vals.Select(v => ((OptCFrameV)v).CF).ToList());
                w.B(0x02);
                foreach (var v in vals) w.B(((OptCFrameV)v).Has ? (byte)1 : (byte)0);
                break;
            case 0x1F: w.Interleave(vals.Select(v => ((RawV)v).Data).ToArray(), 16); break;
            case 0x21: w.Interleave(vals.Select(v => ((RawV)v).Data).ToArray(), 8); break;
            case 0x20:
                foreach (var v in vals)
                {
                    var fv = (FontV)v;
                    w.Str(fv.Family); w.Bytes(BitConverter.GetBytes(fv.Weight)); w.B(fv.Style); w.Str(fv.CachedFaceId);
                }
                break;
            case 0x22:
                {
                    var cvs = vals.Select(v => (ContentV)v).ToList();
                    WInts(w, cvs.Select(c => c.Kind).ToList());
                    var uris = cvs.Where(c => c.Kind == 1).ToList();
                    w.I32(uris.Count); foreach (var c in uris) w.Str(c.Uri);
                    var objs = cvs.Where(c => c.Kind == 2).ToList();
                    w.I32(objs.Count); WRefs(w, objs.Select(c => c.Obj == null ? -1 : c.Obj.Ref).ToList());
                    w.I32(0);
                }
                break;
            default: throw new Exception("cannot write type 0x" + type.ToString("X2"));
        }
    }

    public static object DefaultValue(byte type)
    {
        switch (type)
        {
            case 0x01: return new byte[0];
            case 0x02: return false;
            case 0x03: return 0;
            case 0x04: return 0f;
            case 0x05: return 0.0;
            case 0x06: return new UDimV();
            case 0x07: return new UDim2V();
            case 0x08: return new float[6];
            case 0x09: case 0x0A: return (byte)0;
            case 0x0B: return 194u;
            case 0x12: case 0x1C: return 0u;
            case 0x0C: case 0x0E: return new float[3];
            case 0x0D: return new float[2];
            case 0x10: return new CFrameV { Id = 2 , R = SpecialRotation(2) };
            case 0x13: return null;
            case 0x14: return new short[3];
            case 0x15: return new float[] { 0, 0, 0, 1, 0, 0 };
            case 0x16: return new float[] { 0, 1, 1, 1, 0, 1, 1, 1, 1, 0 };
            case 0x17: return new float[2];
            case 0x18: return new float[4];
            case 0x19: return new PhysV { Flag = 0, Vals = new float[0] };
            case 0x1A: return new byte[3];
            case 0x1B: return 0L;
            case 0x1E: return new OptCFrameV { CF = new CFrameV { Id = 2, R = SpecialRotation(2) }, Has = false };
            case 0x1F: return new RawV { Data = new byte[16] };
            case 0x21: return new RawV { Data = new byte[8] };
            case 0x20: return new FontV { Family = Encoding.UTF8.GetBytes("rbxasset://fonts/families/SourceSansPro.json"), Weight = 400, Style = 0, CachedFaceId = new byte[0] };
            case 0x22: return new ContentV { Kind = 0 };
        }
        throw new Exception("no default for type " + type);
    }

    static byte[] Lz4Literals(byte[] data)
    {
        var o = new MemoryStream();
        int n = data.Length;
        if (n < 15) o.WriteByte((byte)(n << 4));
        else
        {
            o.WriteByte(0xF0);
            int rest = n - 15;
            while (rest >= 255) { o.WriteByte(255); rest -= 255; }
            o.WriteByte((byte)rest);
        }
        o.Write(data, 0, n);
        return o.ToArray();
    }

    static void WriteChunk(Stream s, string name, byte[] data, bool compress)
    {
        var nb = new byte[4];
        var an = Encoding.ASCII.GetBytes(name);
        Array.Copy(an, nb, an.Length);
        s.Write(nb, 0, 4);
        byte[] payload = compress ? Lz4Literals(data) : data;
        s.Write(BitConverter.GetBytes(compress ? payload.Length : 0), 0, 4);
        s.Write(BitConverter.GetBytes(data.Length), 0, 4);
        s.Write(new byte[4], 0, 4);
        s.Write(payload, 0, payload.Length);
    }

    public Dictionary<string, byte[]> WrittenChunks = new Dictionary<string, byte[]>();

    // Every instance reachable from the roots, depth-first so parents always precede children.
    public List<RInst> OrderedInstances()
    {
        var ordered = new List<RInst>();
        var seen = new HashSet<RInst>();
        Action<RInst> walk = null;
        walk = delegate (RInst i)
        {
            if (!seen.Add(i)) return;
            ordered.Add(i);
            foreach (var c in i.Children) walk(c);
        };
        foreach (var r in Instances.Where(i => i.Parent == null)) walk(r);
        foreach (var r in extraRoots) walk(r);
        return ordered;
    }

    List<RInst> extraRoots = new List<RInst>();

    public void Save(string path)
    {
        var all = OrderedInstances();
        // referents: keep original ones, give new instances fresh numbers
        var used = new HashSet<int>();
        foreach (var i in all) if (i.Ref >= 0 && !used.Contains(i.Ref)) used.Add(i.Ref); else i.Ref = -1;
        int next = used.Count == 0 ? 0 : used.Max() + 1;
        foreach (var i in all) if (i.Ref < 0) i.Ref = next++;

        // class ordering: original order first, then new classes sorted
        var classes = new List<string>();
        foreach (var c in ClassNames) if (all.Any(i => i.ClassName == c)) classes.Add(c);
        foreach (var c in all.Select(i => i.ClassName).Distinct().OrderBy(x => x, StringComparer.Ordinal)) if (!classes.Contains(c)) classes.Add(c);

        var fs = new MemoryStream();
        var hdr = new byte[32];
        Array.Copy(Encoding.ASCII.GetBytes("<roblox!"), hdr, 8);
        var sig = new byte[] { 0x89, 0xFF, 0x0D, 0x0A, 0x1A, 0x0A };
        Array.Copy(sig, 0, hdr, 8, 6);
        Array.Copy(BitConverter.GetBytes(classes.Count), 0, hdr, 16, 4);
        Array.Copy(BitConverter.GetBytes(all.Count), 0, hdr, 20, 4);
        fs.Write(hdr, 0, 32);

        if (HadMeta || Meta.Count > 0)
        {
            var w = new W();
            w.I32(Meta.Count);
            foreach (var kv in Meta) { w.Str(kv.Key); w.Str(kv.Value); }
            WriteChunk(fs, "META", w.ToArray(), true);
            WrittenChunks["META"] = w.ToArray();
        }
        if (SharedStrings.Count > 0)
        {
            var w = new W();
            w.I32(0); w.I32(SharedStrings.Count);
            for (int i = 0; i < SharedStrings.Count; i++) { w.Bytes(SharedHashes[i]); w.Str(SharedStrings[i]); }
            WriteChunk(fs, "SSTR", w.ToArray(), true);
            WrittenChunks["SSTR"] = w.ToArray();
        }

        var classInsts = new Dictionary<string, List<RInst>>();
        foreach (var c in classes)
        {
            var list = new List<RInst>();
            List<RInst> orig;
            if (ClassOrder.TryGetValue(c, out orig)) foreach (var i in orig) if (all.Contains(i)) list.Add(i);
            foreach (var i in all) if (i.ClassName == c && !list.Contains(i)) list.Add(i);
            classInsts[c] = list;
        }

        for (int cid = 0; cid < classes.Count; cid++)
        {
            string c = classes[cid];
            var list = classInsts[c];
            var w = new W();
            w.I32(cid); w.Str(c);
            bool svc = list.Any(i => i.IsService);
            w.B(svc ? (byte)1 : (byte)0);
            w.I32(list.Count);
            WRefs(w, list.Select(i => i.Ref).ToList());
            if (svc) foreach (var i in list) w.B(1);
            WriteChunk(fs, "INST", w.ToArray(), true);
            WrittenChunks["INST:" + c] = w.ToArray();
        }

        for (int cid = 0; cid < classes.Count; cid++)
        {
            string c = classes[cid];
            var list = classInsts[c];
            // property set: original order, then any new names
            var props = new List<KeyValuePair<string, byte>>();
            List<KeyValuePair<string, byte>> orig;
            if (ClassProps.TryGetValue(c, out orig)) props.AddRange(orig);
            foreach (var i in list)
                foreach (var p in i.Props)
                    if (!props.Any(x => x.Key == p.Name)) props.Add(new KeyValuePair<string, byte>(p.Name, p.Type));
            foreach (var pk in props)
            {
                var vals = new List<object>();
                foreach (var i in list)
                {
                    var p = i.GetProp(pk.Key);
                    if (p != null && p.Type != pk.Value) throw new Exception("type mismatch for " + c + "." + pk.Key);
                    vals.Add(p != null ? p.Value : DefaultValue(pk.Value));
                }
                var w = new W();
                w.I32(cid); w.Str(pk.Key); w.B(pk.Value);
                WriteValues(w, pk.Value, vals);
                WriteChunk(fs, "PROP", w.ToArray(), true);
                WrittenChunks["PROP:" + c + ":" + pk.Key] = w.ToArray();
            }
        }

        {
            var w = new W();
            w.B(0); w.I32(all.Count);
            WRefs(w, all.Select(i => i.Ref).ToList());
            WRefs(w, all.Select(i => i.Parent == null ? -1 : i.Parent.Ref).ToList());
            WriteChunk(fs, "PRNT", w.ToArray(), true);
            WrittenChunks["PRNT"] = w.ToArray();
        }
        WriteChunk(fs, "END", Encoding.ASCII.GetBytes("</roblox>"), false);
        File.WriteAllBytes(path, fs.ToArray());
    }
}
