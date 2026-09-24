using System;
using System.IO;
using System.Linq;
using System.Text;

public static class Program
{
    public static int Main(string[] args)
    {
        try
        {
            string cmd = args[0];
            if (cmd == "tree")
            {
                var f = RbxFile.Load(args[1]);
                Dump.Tree(f, Console.Out, args.Length > 2 && args[2] == "props");
            }
            else if (cmd == "scripts")
            {
                var f = RbxFile.Load(args[1]);
                Directory.CreateDirectory(args[2]);
                foreach (var i in f.Instances)
                {
                    var src = i.GetProp("Source");
                    if (src == null) continue;
                    string fn = i.Ref + "_" + i.Name.Replace(" ", "_") + ".lua";
                    File.WriteAllBytes(Path.Combine(args[2], fn), (byte[])src.Value);
                    Console.WriteLine(fn + " (" + ((byte[])src.Value).Length + " bytes)");
                }
            }
            else if (cmd == "roundtrip")
            {
                var f = RbxFile.Load(args[1]);
                f.Save(args[2]);
                int same = 0, diff = 0;
                foreach (var kv in f.OriginalChunks)
                {
                    byte[] w;
                    if (!f.WrittenChunks.TryGetValue(kv.Key, out w)) { Console.WriteLine("MISSING " + kv.Key); diff++; continue; }
                    if (w.SequenceEqual(kv.Value)) same++;
                    else { Console.WriteLine("DIFF " + kv.Key + " orig=" + kv.Value.Length + " new=" + w.Length); diff++; }
                }
                foreach (var k in f.WrittenChunks.Keys) if (!f.OriginalChunks.ContainsKey(k)) Console.WriteLine("EXTRA " + k);
                Console.WriteLine("identical chunks: " + same + ", differing: " + diff);
                var g = RbxFile.Load(args[2]);
                Console.WriteLine("reloaded: " + g.Instances.Count + " instances");
            }
            else if (cmd == "lint")
            {
                int total = 0, files = 0;
                foreach (var file in Directory.GetFiles(args[1], "*.lua", SearchOption.AllDirectories).OrderBy(x => x))
                {
                    files++;
                    string display = file.Substring(args[1].Length).TrimStart('\\', '/');
                    foreach (var p in LuaCheck.Check(file, display)) { Console.WriteLine(p); total++; }
                }
                Console.WriteLine(files + " files, " + total + " problems");
                return total == 0 ? 0 : 3;
            }
            else if (cmd == "build")
            {
                // build <original.rbxl> <srcDir> <out.rbxl>
                var f = RbxFile.Load(args[1]);
                var b = new Builder(f);
                b.Run(args[2]);
                f.Save(args[3]);
                foreach (var line in b.Log) Console.WriteLine(line);
                var g = RbxFile.Load(args[3]);
                Console.WriteLine("saved " + args[3] + ": " + g.Instances.Count + " instances, " + new FileInfo(args[3]).Length + " bytes");
            }
            else
            {
                Console.Error.WriteLine("unknown command");
                return 2;
            }
            return 0;
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e.ToString());
            return 1;
        }
    }
}
