// Builds the Smash place: archives the old scripts/stage, adds the arena and imports src/*.lua.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

public class Builder
{
    RbxFile f;
    Random rng = new Random(20260923);
    uint uidIndex = 1;
    byte[] uidSession;
    Dictionary<string, RInst> templates = new Dictionary<string, RInst>();
    public List<string> Log = new List<string>();

    public Builder(RbxFile file)
    {
        f = file;
        uidSession = new byte[12];
        rng.NextBytes(uidSession);
    }

    // ---------------- helpers ----------------
    RInst Service(string className)
    {
        return f.Roots.First(r => r.ClassName == className);
    }

    static RProp Clone(RProp p)
    {
        object v = p.Value;
        if (v is byte[]) v = ((byte[])v).ToArray();
        else if (v is float[]) v = ((float[])v).ToArray();
        else if (v is CFrameV) { var c = (CFrameV)v; v = new CFrameV { Id = c.Id, R = c.R.ToArray(), P = c.P.ToArray() }; }
        else if (v is RawV) v = new RawV { Data = ((RawV)v).Data.ToArray() };
        else if (v is PhysV) { var ph = (PhysV)v; v = new PhysV { Flag = ph.Flag, Vals = ph.Vals.ToArray() }; }
        else if (v is OptCFrameV) { var o = (OptCFrameV)v; v = new OptCFrameV { Has = o.Has, CF = new CFrameV { Id = o.CF.Id, R = o.CF.R.ToArray(), P = o.CF.P.ToArray() } }; }
        return new RProp(p.Name, p.Type, v);
    }

    byte[] NewUniqueId()
    {
        var b = new byte[16];
        uint i = uidIndex++;
        b[0] = (byte)(i >> 24); b[1] = (byte)(i >> 16); b[2] = (byte)(i >> 8); b[3] = (byte)i;
        Array.Copy(uidSession, 0, b, 4, 12);
        return b;
    }

    string NewGuid()
    {
        var bytes = new byte[16];
        rng.NextBytes(bytes);
        return "{" + new Guid(bytes).ToString().ToUpperInvariant() + "}";
    }

    public static void Set(RInst i, string name, byte type, object value)
    {
        var p = i.GetProp(name);
        if (p == null) i.Props.Add(new RProp(name, type, value));
        else
        {
            if (p.Type != type) throw new Exception("type mismatch setting " + i.ClassName + "." + name);
            p.Value = value;
        }
    }
    static void SetStr(RInst i, string name, string v) { Set(i, name, 0x01, Encoding.UTF8.GetBytes(v)); }
    static void SetBool(RInst i, string name, bool v) { Set(i, name, 0x02, v); }
    static void SetFloat(RInst i, string name, float v) { Set(i, name, 0x04, v); }
    static void SetEnum(RInst i, string name, uint v) { Set(i, name, 0x12, v); }
    static void SetIfPresent(RInst i, string name, object v)
    {
        var p = i.GetProp(name);
        if (p != null) p.Value = v;
    }

    RInst FromTemplate(RInst template, string name, RInst parent)
    {
        var n = new RInst { ClassName = template.ClassName };
        foreach (var p in template.Props) n.Props.Add(Clone(p));
        SetStr(n, "Name", name);
        var uid = n.GetProp("UniqueId");
        if (uid != null) uid.Value = new RawV { Data = NewUniqueId() };
        var guid = n.GetProp("ScriptGuid");
        if (guid != null) guid.Value = Encoding.UTF8.GetBytes(NewGuid());
        n.SetParent(parent);
        return n;
    }

    // A bare instance carrying the properties every Instance serializes
    RInst NewInstance(string className, string name, RInst parent)
    {
        var n = new RInst { ClassName = className };
        n.Props.Add(new RProp("AttributesSerialize", 0x01, new byte[0]));
        n.Props.Add(new RProp("Capabilities", 0x21, new RawV { Data = new byte[8] }));
        n.Props.Add(new RProp("DefinesCapabilities", 0x02, false));
        n.Props.Add(new RProp("HistoryId", 0x1F, new RawV { Data = new byte[16] }));
        n.Props.Add(new RProp("Name", 0x01, Encoding.UTF8.GetBytes(name)));
        n.Props.Add(new RProp("SourceAssetId", 0x1B, -1L));
        n.Props.Add(new RProp("Tags", 0x1C, 0u));
        n.Props.Add(new RProp("UniqueId", 0x1F, new RawV { Data = NewUniqueId() }));
        n.SetParent(parent);
        return n;
    }

    RInst Folder(string name, RInst parent)
    {
        return NewInstance("Folder", name, parent);
    }

    // Euler angles in degrees, Roblox CFrame.Angles order (R = Rx * Ry * Rz), row-major
    static float[] Rotation(double rx, double ry, double rz)
    {
        double a = rx * Math.PI / 180, b = ry * Math.PI / 180, c = rz * Math.PI / 180;
        double[,] X = { { 1, 0, 0 }, { 0, Math.Cos(a), -Math.Sin(a) }, { 0, Math.Sin(a), Math.Cos(a) } };
        double[,] Y = { { Math.Cos(b), 0, Math.Sin(b) }, { 0, 1, 0 }, { -Math.Sin(b), 0, Math.Cos(b) } };
        double[,] Z = { { Math.Cos(c), -Math.Sin(c), 0 }, { Math.Sin(c), Math.Cos(c), 0 }, { 0, 0, 1 } };
        var XY = Mul(X, Y);
        var R = Mul(XY, Z);
        var o = new float[9];
        for (int r = 0; r < 3; r++) for (int col = 0; col < 3; col++) o[r * 3 + col] = (float)Math.Round(R[r, col], 6);
        return o;
    }
    static double[,] Mul(double[,] A, double[,] B)
    {
        var C = new double[3, 3];
        for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) for (int k = 0; k < 3; k++) C[i, j] += A[i, k] * B[k, j];
        return C;
    }
    static CFrameV CF(float x, float y, float z, double rx = 0, double ry = 0, double rz = 0)
    {
        if (rx == 0 && ry == 0 && rz == 0)
            return new CFrameV { Id = 2, R = RbxFile.SpecialRotation(2), P = new[] { x, y, z } };
        return new CFrameV { Id = 0, R = Rotation(rx, ry, rz), P = new[] { x, y, z } };
    }

    // Enum.Material values
    public const uint Plastic = 256, SmoothPlastic = 272, Neon = 288, Marble = 784, Basalt = 788, Slate = 800,
        Concrete = 816, Granite = 832, Rock = 896, Glass = 1568, ForceField = 1584;

    RInst Part(RInst parent, string name, float[] pos, float[] size, int r, int g, int b, uint material,
        float transparency = 0, bool collide = false, uint shape = 1, double rx = 0, double ry = 0, double rz = 0, bool query = true)
    {
        var p = FromTemplate(templates["Part"], name, parent);
        Set(p, "CFrame", 0x10, CF(pos[0], pos[1], pos[2], rx, ry, rz));
        Set(p, "size", 0x0E, size);
        Set(p, "Color3uint8", 0x1A, new byte[] { (byte)r, (byte)g, (byte)b });
        SetEnum(p, "Material", material);
        SetFloat(p, "Transparency", transparency);
        SetBool(p, "CanCollide", collide);
        SetBool(p, "CanQuery", query);
        SetBool(p, "CanTouch", collide);
        SetBool(p, "Anchored", true);
        SetBool(p, "Locked", false);
        SetBool(p, "CastShadow", transparency < 0.9);
        SetEnum(p, "shape", shape);
        SetEnum(p, "TopSurface", 0);
        SetEnum(p, "BottomSurface", 0);
        return p;
    }

    static float[] V(float x, float y, float z) { return new[] { x, y, z }; }

    // ---------------- steps ----------------
    public void Run(string srcDir)
    {
        var workspace = Service("Workspace");
        var serverStorage = Service("ServerStorage");
        var sss = Service("ServerScriptService");
        var starterPlayer = Service("StarterPlayer");
        var players = Service("Players");
        var sps = starterPlayer.Find("StarterPlayerScripts");
        var scs = starterPlayer.Find("StarterCharacterScripts");

        // templates (captured before anything is modified)
        templates["Part"] = workspace.Children.First(c => c.ClassName == "Part" && c.Name == "Part");
        templates["Script"] = sss.Find("PlayerDodgeIntangibleServer");
        templates["LocalScript"] = sps.Find("PlayerDodgeIntangible");
        templates["ModuleScript"] = sss.Find("ShieldManager");
        var snapshot = new Dictionary<string, RInst>();
        foreach (var kv in templates)
        {
            var copy = new RInst { ClassName = kv.Value.ClassName };
            foreach (var p in kv.Value.Props) copy.Props.Add(Clone(p));
            snapshot[kv.Key] = copy;
        }
        templates = snapshot;

        // 1. archive the old prototype so nothing is lost
        var legacy = Folder("Legacy", serverStorage);
        var oldStage = Folder("OldStage", legacy);
        var oldChar = Folder("OldStarterCharacterScripts", legacy);
        var oldPlayer = Folder("OldStarterPlayerScripts", legacy);
        var oldServer = Folder("OldServerScripts", legacy);
        foreach (var c in workspace.Children.ToList())
        {
            if (c.ClassName == "Part") { c.SetParent(oldStage); Log.Add("archived Workspace." + c.Name); }
        }
        foreach (var c in scs.Children.ToList()) { c.SetParent(oldChar); Log.Add("archived StarterCharacterScripts." + c.Name); }
        foreach (var c in sps.Children.ToList()) { c.SetParent(oldPlayer); Log.Add("archived StarterPlayerScripts." + c.Name); }
        foreach (var c in sss.Children.ToList()) { c.SetParent(oldServer); Log.Add("archived ServerScriptService." + c.Name); }
        Action<RInst> disable = null;
        disable = delegate (RInst i)
        {
            if (i.ClassName == "Script" || i.ClassName == "LocalScript") SetIfPresent(i, "Disabled", true);
            foreach (var c in i.Children) disable(c);
        };
        disable(legacy);

        // 2. world + player settings
        SetFloat(workspace, "Gravity", 160f);
        SetIfPresent(workspace, "StreamingEnabled", false);
        SetIfPresent(players, "CharacterAutoLoads", false);
        SetIfPresent(starterPlayer, "LoadCharacterAppearance", false);
        SetIfPresent(starterPlayer, "AutoJumpEnabled", false);
        SetIfPresent(starterPlayer, "EnableMouseLockOption", false);
        SetIfPresent(starterPlayer, "DevComputerMovementMode", 3u); // Scriptable: the game drives movement
        SetIfPresent(starterPlayer, "DevTouchMovementMode", 5u);    // Scriptable

        var spawn = workspace.Children.FirstOrDefault(c => c.ClassName == "SpawnLocation");
        if (spawn != null)
        {
            Set(spawn, "CFrame", 0x10, CF(0, 51.5f, 0));
            SetFloat(spawn, "Transparency", 1f);
            SetBool(spawn, "CanCollide", false);
            SetBool(spawn, "CanQuery", false);
            SetBool(spawn, "CanTouch", false);
            SetBool(spawn, "Anchored", true);
            foreach (var c in spawn.Children) if (c.ClassName == "Decal") SetFloat(c, "Transparency", 1f);
        }

        BuildStage(workspace);

        // 3. scripts
        foreach (var dir in Directory.GetDirectories(srcDir))
        {
            string serviceName = Path.GetFileName(dir);
            var service = f.Roots.FirstOrDefault(r => r.Name == serviceName || r.ClassName == serviceName);
            if (service == null) throw new Exception("no service named " + serviceName);
            Import(service, dir);
        }
    }

    void BuildStage(RInst workspace)
    {
        var stage = NewInstance("Model", "SmashStage", workspace);
        stage.Props.Add(new RProp("LevelOfDetail", 0x12, 0u));
        stage.Props.Add(new RProp("ModelStreamingMode", 0x12, 0u));
        stage.Props.Add(new RProp("NeedsPivotMigration", 0x02, false));
        stage.Props.Add(new RProp("PrimaryPart", 0x13, null));
        stage.Props.Add(new RProp("WorldPivotData", 0x1E, new OptCFrameV { Has = true, CF = CF(0, 50, 0) }));

        // the fighting surface: top at y = 50, ledges at x = +-36
        Part(stage, "Main", V(0, 47, 0), V(72, 6, 16), 58, 64, 88, Slate, 0, true);
        // glowing trim + ledge lights
        Part(stage, "TrimFront", V(0, 49.75f, 8.1f), V(72.4f, 0.5f, 0.25f), 0, 225, 255, Neon);
        Part(stage, "TrimTop", V(0, 50.08f, 0), V(72.2f, 0.16f, 16.2f), 86, 94, 124, SmoothPlastic);
        Part(stage, "LedgeLightL", V(-36, 50, 8.1f), V(1.2f, 1.2f, 1.2f), 255, 255, 255, Neon);
        Part(stage, "LedgeLightR", V(36, 50, 8.1f), V(1.2f, 1.2f, 1.2f), 255, 255, 255, Neon);
        // floating-island underside
        Part(stage, "Under1", V(0, 41.5f, 0), V(62, 5, 14.5f), 70, 60, 86, Basalt);
        Part(stage, "Under2", V(0, 37, 0), V(46, 4, 13), 58, 48, 72, Basalt);
        Part(stage, "Under3", V(0, 33, 0), V(28, 4, 11), 46, 38, 60, Rock);
        Part(stage, "Under4", V(0, 29.5f, 0), V(12, 3, 9), 36, 30, 48, Rock);
        Part(stage, "UnderTrim", V(0, 43.9f, 7.35f), V(62, 0.3f, 0.2f), 150, 80, 255, Neon);
        // crystals hanging under the island
        Part(stage, "CrystalA", V(-18, 36, 5), V(1.6f, 6, 1.6f), 0, 225, 255, Neon, 0.1f, false, 1, 0, 45, 18);
        Part(stage, "CrystalB", V(17, 35, 4.5f), V(1.4f, 5, 1.4f), 190, 90, 255, Neon, 0.1f, false, 1, 0, 45, -15);
        Part(stage, "CrystalC", V(-6, 29, 3.5f), V(1.2f, 5, 1.2f), 255, 90, 200, Neon, 0.1f, false, 1, 0, 45, 8);
        Part(stage, "CrystalD", V(8, 27.5f, 3), V(1.8f, 7, 1.8f), 0, 225, 255, Neon, 0.1f, false, 1, 0, 45, -6);

        // pass-through platforms (hold S to drop, jump up through them)
        var plats = NewInstance("Folder", "Platforms", stage);
        Part(plats, "Platform1", V(-20, 63.5f, 0), V(18, 1, 10), 120, 200, 255, Glass, 0.35f, true);
        Part(plats, "Platform2", V(20, 63.5f, 0), V(18, 1, 10), 120, 200, 255, Glass, 0.35f, true);
        Part(plats, "Platform3", V(0, 77, 0), V(18, 1, 10), 120, 200, 255, Glass, 0.35f, true);
        Part(stage, "PlatTrim1", V(-20, 63, 5.1f), V(18, 0.25f, 0.2f), 0, 225, 255, Neon);
        Part(stage, "PlatTrim2", V(20, 63, 5.1f), V(18, 0.25f, 0.2f), 0, 225, 255, Neon);
        Part(stage, "PlatTrim3", V(0, 76.5f, 5.1f), V(18, 0.25f, 0.2f), 255, 200, 60, Neon);

        // spawn markers
        var spawns = NewInstance("Folder", "Spawns", stage);
        float[] xs = { -24, 24, -8, 8 };
        for (int i = 0; i < 4; i++)
            Part(spawns, "Spawn" + (i + 1), V(xs[i], 51, 0), V(2, 1, 2), 255, 255, 255, SmoothPlastic, 1f, false, 1, 0, 0, 0, false);

        // background scenery for depth
        var bg = NewInstance("Folder", "Background", stage);
        Part(bg, "Moon", V(60, 175, -420), V(90, 90, 90), 255, 236, 205, Neon, 0.05f, false, 0);
        Part(bg, "IslandFarL", V(-150, 20, -220), V(50, 14, 40), 64, 56, 84, Basalt);
        Part(bg, "IslandFarLRock", V(-150, 8, -220), V(30, 16, 26), 46, 40, 62, Rock);
        Part(bg, "IslandFarR", V(165, 45, -260), V(60, 16, 44), 64, 56, 84, Basalt);
        Part(bg, "IslandFarRRock", V(165, 30, -260), V(34, 18, 28), 46, 40, 62, Rock);
        Part(bg, "PillarL", V(-95, 10, -150), V(14, 90, 14), 80, 74, 104, Marble, 0, false, 1, 0, 25, 0);
        Part(bg, "PillarR", V(105, 20, -170), V(14, 110, 14), 80, 74, 104, Marble, 0, false, 1, 0, -20, 0);
        Part(bg, "PillarLCap", V(-95, 56, -150), V(18, 3, 18), 0, 225, 255, Neon, 0, false, 1, 0, 25, 0);
        Part(bg, "PillarRCap", V(105, 76, -170), V(18, 3, 18), 190, 90, 255, Neon, 0, false, 1, 0, -20, 0);
        Part(bg, "RockA", V(-60, 95, -130), V(8, 6, 7), 70, 62, 90, Rock, 0, false, 1, 20, 35, 10);
        Part(bg, "RockB", V(70, 105, -140), V(10, 7, 8), 70, 62, 90, Rock, 0, false, 1, -15, 60, 25);
        Part(bg, "RockC", V(-20, 125, -200), V(12, 8, 10), 70, 62, 90, Rock, 0, false, 1, 30, 10, -20);
        Part(bg, "RockD", V(130, 120, -230), V(9, 6, 9), 70, 62, 90, Rock, 0, false, 1, 10, 45, 40);
        Log.Add("built SmashStage");
    }

    static string ScriptName(string file, out string cls)
    {
        string n = Path.GetFileName(file);
        if (n.EndsWith(".server.lua")) { cls = "Script"; return n.Substring(0, n.Length - 11); }
        if (n.EndsWith(".client.lua")) { cls = "LocalScript"; return n.Substring(0, n.Length - 11); }
        cls = "ModuleScript";
        return n.Substring(0, n.Length - 4);
    }

    static byte[] ReadSource(string path)
    {
        var b = File.ReadAllBytes(path);
        if (b.Length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF) b = b.Skip(3).ToArray();
        // normalize CRLF to LF like Studio does
        var s = Encoding.UTF8.GetString(b).Replace("\r\n", "\n");
        return Encoding.UTF8.GetBytes(s);
    }

    RInst MakeScript(string cls, string name, byte[] source, RInst parent)
    {
        var s = FromTemplate(templates[cls], name, parent);
        Set(s, "Source", 0x01, source);
        SetIfPresent(s, "Disabled", false);
        return s;
    }

    void Import(RInst parent, string dir)
    {
        foreach (var sub in Directory.GetDirectories(dir).OrderBy(x => x, StringComparer.Ordinal))
        {
            string name = Path.GetFileName(sub);
            RInst node;
            string init = null, cls = null;
            foreach (var cand in new[] { "init.server.lua", "init.client.lua", "init.lua" })
            {
                if (File.Exists(Path.Combine(sub, cand)))
                {
                    init = Path.Combine(sub, cand);
                    cls = cand == "init.server.lua" ? "Script" : cand == "init.client.lua" ? "LocalScript" : "ModuleScript";
                    break;
                }
            }
            if (init != null)
            {
                node = MakeScript(cls, name, ReadSource(init), parent);
                Log.Add("script " + node.Path() + " (" + cls + ")");
            }
            else
            {
                node = parent.Find(name) ?? Folder(name, parent);
            }
            Import(node, sub);
        }
        foreach (var file in Directory.GetFiles(dir, "*.lua").OrderBy(x => x, StringComparer.Ordinal))
        {
            string fn = Path.GetFileName(file);
            if (fn.StartsWith("init.")) continue;
            string cls;
            string name = ScriptName(file, out cls);
            var s = MakeScript(cls, name, ReadSource(file), parent);
            Log.Add("script " + s.Path() + " (" + cls + ")");
        }
    }
}
