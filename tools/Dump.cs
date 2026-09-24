using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

public static class Dump
{
    public static string Fmt(RProp p)
    {
        var v = p.Value;
        if (v == null) return "null";
        if (v is byte[] && p.Type == 0x01)
        {
            var b = (byte[])v;
            string s = Encoding.UTF8.GetString(b);
            bool printable = b.All(x => x >= 9 && x != 11 && x != 12 && (x >= 32 || x == 9 || x == 10 || x == 13) || x >= 128);
            if (!printable) return "<binary " + b.Length + " bytes: " + BitConverter.ToString(b.Take(48).ToArray()) + ">";
            if (s.Length > 120) return "\"" + s.Substring(0, 120).Replace("\n", "\\n") + "...\" (" + s.Length + " chars)";
            return "\"" + s.Replace("\n", "\\n") + "\"";
        }
        if (v is byte[]) return string.Join(",", ((byte[])v).Select(x => x.ToString()));
        if (v is float[]) return "(" + string.Join(", ", ((float[])v).Select(x => x.ToString("R"))) + ")";
        if (v is short[]) return "(" + string.Join(", ", ((short[])v).Select(x => x.ToString())) + ")";
        if (v is UDimV) { var u = (UDimV)v; return "UDim(" + u.S + "," + u.O + ")"; }
        if (v is UDim2V) { var u = (UDim2V)v; return "UDim2(" + u.XS + "," + u.XO + "," + u.YS + "," + u.YO + ")"; }
        if (v is CFrameV) { var c = (CFrameV)v; return "CF[id=" + c.Id + "](" + string.Join(",", c.P) + " | " + string.Join(",", c.R) + ")"; }
        if (v is OptCFrameV) { var o = (OptCFrameV)v; return o.Has ? "OptCF(" + string.Join(",", o.CF.P) + ")" : "OptCF(none)"; }
        if (v is PhysV) { var ph = (PhysV)v; return "Phys(flag=" + ph.Flag + " " + string.Join(",", ph.Vals) + ")"; }
        if (v is FontV) { var f = (FontV)v; return "Font(" + Encoding.UTF8.GetString(f.Family) + "," + f.Weight + "," + f.Style + ")"; }
        if (v is RawV) return "raw:" + BitConverter.ToString(((RawV)v).Data);
        if (v is ContentV) { var c = (ContentV)v; return c.Kind == 0 ? "Content(none)" : c.Kind == 1 ? "Content(" + Encoding.UTF8.GetString(c.Uri) + ")" : "Content(obj " + (c.Obj == null ? "null" : c.Obj.Path()) + ")"; }
        if (v is RInst) return "-> " + ((RInst)v).Path();
        if (v is float) return ((float)v).ToString("R");
        return v.ToString();
    }

    public static void Tree(RbxFile f, TextWriter o, bool props)
    {
        Action<RInst, int> walk = null;
        walk = delegate (RInst i, int depth)
        {
            string ind = new string(' ', depth * 2);
            o.WriteLine(ind + i.ClassName + " \"" + i.Name + "\"" + (i.IsService ? " [service]" : "") + " ref=" + i.Ref);
            if (props)
                foreach (var p in i.Props)
                    if (p.Name != "Name") o.WriteLine(ind + "    ." + p.Name + " (0x" + p.Type.ToString("X2") + ") = " + Fmt(p));
            foreach (var c in i.Children) walk(c, depth + 1);
        };
        foreach (var r in f.Roots) walk(r, 0);
    }
}
