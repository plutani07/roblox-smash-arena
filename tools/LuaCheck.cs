// Minimal Luau parser + scope checker: reports syntax errors and names that are never declared.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;

public class LuaCheck
{
    enum K { Name, Number, String, Symbol, Keyword, EOF }
    class Tok { public K Kind; public string Text; public int Line; }

    static readonly HashSet<string> Keywords = new HashSet<string> {
        "and","break","do","else","elseif","end","false","for","function","if","in","local","nil","not","or",
        "repeat","return","then","true","until","while"
    };
    static readonly string[] Symbols = {
        "...","..=","//=","..","==","~=","<=",">=","+=","-=","*=","/=","%=","^=","//","::","->",
        "+","-","*","/","%","^","#","&","~","|","<",">","=","(",")","{","}","[","]",";",":",",","."
    };
    public static readonly HashSet<string> Globals = new HashSet<string> {
        "game","workspace","script","plugin","shared","_G","Enum","Instance","Vector3","Vector2","Vector3int16","Vector2int16",
        "CFrame","Color3","UDim","UDim2","BrickColor","Ray","Rect","Region3","NumberRange","NumberSequence",
        "NumberSequenceKeypoint","ColorSequence","ColorSequenceKeypoint","TweenInfo","RaycastParams","OverlapParams",
        "PhysicalProperties","Random","DateTime","Font","Faces","Axes","PathWaypoint","CatalogSearchParams",
        "math","string","table","task","os","coroutine","debug","utf8","bit32","buffer",
        "pairs","ipairs","next","print","warn","error","assert","require","tostring","tonumber","type","typeof",
        "pcall","xpcall","select","unpack","rawget","rawset","rawequal","rawlen","setmetatable","getmetatable",
        "tick","time","wait","delay","spawn","elapsedTime","newproxy","gcinfo","collectgarbage","settings","UserSettings",
        "version","printidentity","SharedTable",
    };

    List<Tok> toks;
    int pos;
    string file;
    public List<string> Problems = new List<string>();
    List<HashSet<string>> scopes = new List<HashSet<string>>();

    // ---------------- lexer ----------------
    static List<Tok> Lex(string src, string file, List<string> problems)
    {
        var list = new List<Tok>();
        int i = 0, line = 1, n = src.Length;
        Func<int, char> at = k => k < n ? src[k] : '\0';
        while (i < n)
        {
            char c = src[i];
            if (c == '\n') { line++; i++; continue; }
            if (char.IsWhiteSpace(c)) { i++; continue; }
            if (c == '-' && at(i + 1) == '-')
            {
                i += 2;
                int lvl = LongBracket(src, i);
                if (lvl >= 0)
                {
                    int end = src.IndexOf("]" + new string('=', lvl) + "]", i, StringComparison.Ordinal);
                    if (end < 0) { problems.Add(file + ":" + line + ": unterminated long comment"); return list; }
                    line += src.Substring(i, end - i).Count(ch => ch == '\n');
                    i = end + lvl + 2;
                }
                else { while (i < n && src[i] != '\n') i++; }
                continue;
            }
            int startLine = line;
            if (c == '"' || c == '\'' || c == '`')
            {
                int j = i + 1;
                var sb = new StringBuilder();
                while (j < n && src[j] != c)
                {
                    if (src[j] == '\\') { if (at(j + 1) == '\n') line++; j += 2; continue; }
                    if (src[j] == '\n' && c != '`') { problems.Add(file + ":" + line + ": unfinished string"); break; }
                    if (src[j] == '\n') line++;
                    sb.Append(src[j]);
                    j++;
                }
                list.Add(new Tok { Kind = K.String, Text = sb.ToString(), Line = startLine });
                i = j + 1;
                continue;
            }
            if (c == '[')
            {
                int lvl = LongBracket(src, i);
                if (lvl >= 0)
                {
                    int open = i + lvl + 2;
                    int end = src.IndexOf("]" + new string('=', lvl) + "]", open, StringComparison.Ordinal);
                    if (end < 0) { problems.Add(file + ":" + line + ": unterminated long string"); return list; }
                    line += src.Substring(open, end - open).Count(ch => ch == '\n');
                    list.Add(new Tok { Kind = K.String, Text = src.Substring(open, end - open), Line = startLine });
                    i = end + lvl + 2;
                    continue;
                }
            }
            if (char.IsDigit(c) || (c == '.' && char.IsDigit(at(i + 1))))
            {
                int j = i;
                if (c == '0' && (at(i + 1) == 'x' || at(i + 1) == 'X' || at(i + 1) == 'b' || at(i + 1) == 'B')) j += 2;
                while (j < n && (char.IsLetterOrDigit(src[j]) || src[j] == '.' || src[j] == '_' ||
                    ((src[j] == '+' || src[j] == '-') && (src[j - 1] == 'e' || src[j - 1] == 'E') && !(src.Substring(i, 2) == "0x")))) j++;
                list.Add(new Tok { Kind = K.Number, Text = src.Substring(i, j - i), Line = line });
                i = j;
                continue;
            }
            if (char.IsLetter(c) || c == '_')
            {
                int j = i;
                while (j < n && (char.IsLetterOrDigit(src[j]) || src[j] == '_')) j++;
                string w = src.Substring(i, j - i);
                list.Add(new Tok { Kind = Keywords.Contains(w) ? K.Keyword : K.Name, Text = w, Line = line });
                i = j;
                continue;
            }
            bool matched = false;
            foreach (var s in Symbols)
            {
                if (string.CompareOrdinal(src, i, s, 0, s.Length) == 0)
                {
                    list.Add(new Tok { Kind = K.Symbol, Text = s, Line = line });
                    i += s.Length;
                    matched = true;
                    break;
                }
            }
            if (!matched)
            {
                if (c > 127) { i++; continue; }
                problems.Add(file + ":" + line + ": unexpected character '" + c + "'");
                i++;
            }
        }
        list.Add(new Tok { Kind = K.EOF, Text = "<eof>", Line = line });
        return list;
    }

    static int LongBracket(string s, int i)
    {
        if (i >= s.Length || s[i] != '[') return -1;
        int j = i + 1, lvl = 0;
        while (j < s.Length && s[j] == '=') { lvl++; j++; }
        return (j < s.Length && s[j] == '[') ? lvl : -1;
    }

    // ---------------- parser helpers ----------------
    class ParseError : Exception { public ParseError(string m) : base(m) { } }

    Tok Peek { get { return toks[pos]; } }
    Tok PeekAt(int k) { return toks[Math.Min(pos + k, toks.Count - 1)]; }
    Tok Next() { return toks[pos++]; }
    bool Is(string text) { var t = Peek; return (t.Kind == K.Symbol || t.Kind == K.Keyword) && t.Text == text; }
    bool Accept(string text) { if (Is(text)) { pos++; return true; } return false; }
    void Expect(string text, string context)
    {
        if (!Accept(text)) throw new ParseError(file + ":" + Peek.Line + ": expected '" + text + "' " + context + " near '" + Peek.Text + "'");
    }
    string ExpectName(string context)
    {
        if (Peek.Kind != K.Name) throw new ParseError(file + ":" + Peek.Line + ": expected name " + context + " near '" + Peek.Text + "'");
        return Next().Text;
    }

    void Push() { scopes.Add(new HashSet<string>()); }
    void Pop() { scopes.RemoveAt(scopes.Count - 1); }
    void Declare(string name) { scopes[scopes.Count - 1].Add(name); }
    bool Resolves(string name)
    {
        for (int i = scopes.Count - 1; i >= 0; i--) if (scopes[i].Contains(name)) return true;
        return Globals.Contains(name);
    }
    void Use(string name, int line)
    {
        if (!Resolves(name)) Problems.Add(file + ":" + line + ": unknown name '" + name + "'");
    }

    // ---------------- grammar ----------------
    bool BlockEnd()
    {
        var t = Peek;
        return t.Kind == K.EOF || (t.Kind == K.Keyword && (t.Text == "end" || t.Text == "else" || t.Text == "elseif" || t.Text == "until"));
    }

    void Block()
    {
        while (!BlockEnd())
        {
            if (Is("return"))
            {
                Next();
                if (!BlockEnd() && !Is(";")) ExpList();
                Accept(";");
                if (!BlockEnd()) throw new ParseError(file + ":" + Peek.Line + ": code after return near '" + Peek.Text + "'");
                return;
            }
            Statement();
            Accept(";");
        }
    }

    void Statement()
    {
        var t = Peek;
        if (t.Kind == K.Keyword)
        {
            switch (t.Text)
            {
                case "local":
                    Next();
                    if (Accept("function"))
                    {
                        string name = ExpectName("after 'local function'");
                        Declare(name);
                        FuncBody(false);
                    }
                    else
                    {
                        var names = new List<string>();
                        do { names.Add(ExpectName("in local declaration")); SkipType(); } while (Accept(","));
                        if (Accept("=")) ExpList();
                        foreach (var nm in names) Declare(nm);
                    }
                    return;
                case "function":
                    {
                        Next();
                        int line = Peek.Line;
                        string first = ExpectName("after 'function'");
                        bool method = false;
                        bool dotted = false;
                        while (Is(".") || Is(":"))
                        {
                            if (Next().Text == ":") method = true;
                            dotted = true;
                            ExpectName("in function name");
                        }
                        if (dotted || Resolves(first)) Use(first, line);
                        else Problems.Add(file + ":" + line + ": global function '" + first + "'");
                        FuncBody(method);
                        return;
                    }
                case "if":
                    Next(); Expr(); Expect("then", "after if condition");
                    Push(); Block(); Pop();
                    while (Accept("elseif")) { Expr(); Expect("then", "after elseif condition"); Push(); Block(); Pop(); }
                    if (Accept("else")) { Push(); Block(); Pop(); }
                    Expect("end", "to close 'if' (line " + t.Line + ")");
                    return;
                case "while":
                    Next(); Expr(); Expect("do", "after while condition");
                    Push(); Block(); Pop();
                    Expect("end", "to close 'while' (line " + t.Line + ")");
                    return;
                case "repeat":
                    Next(); Push(); Block();
                    Expect("until", "to close 'repeat' (line " + t.Line + ")");
                    Expr(); Pop();
                    return;
                case "do":
                    Next(); Push(); Block(); Pop();
                    Expect("end", "to close 'do' (line " + t.Line + ")");
                    return;
                case "for":
                    {
                        Next();
                        var names = new List<string>();
                        names.Add(ExpectName("in for loop")); SkipType();
                        if (Accept("="))
                        {
                            Expr(); Expect(",", "in numeric for"); Expr();
                            if (Accept(",")) Expr();
                        }
                        else
                        {
                            while (Accept(",")) { names.Add(ExpectName("in for loop")); SkipType(); }
                            Expect("in", "in generic for");
                            ExpList();
                        }
                        Expect("do", "in for loop");
                        Push();
                        foreach (var nm in names) Declare(nm);
                        Block();
                        Pop();
                        Expect("end", "to close 'for' (line " + t.Line + ")");
                        return;
                    }
                case "break":
                    Next();
                    return;
            }
        }
        if (t.Kind == K.Name && t.Text == "continue" && (PeekAt(1).Kind == K.Keyword || PeekAt(1).Kind == K.EOF || PeekAt(1).Text == ";"))
        {
            Next();
            return;
        }
        // expression statement: call or assignment
        int line0 = Peek.Line;
        bool isCall;
        string rootName;
        SuffixedExpr(out isCall, out rootName, true);
        if (Is("=") || Is(","))
        {
            while (Accept(",")) { bool c2; string r2; SuffixedExpr(out c2, out r2, true); }
            Expect("=", "in assignment");
            ExpList();
            return;
        }
        foreach (var op in new[] { "+=", "-=", "*=", "/=", "%=", "^=", "..=", "//=" })
        {
            if (Accept(op)) { Expr(); return; }
        }
        if (!isCall) throw new ParseError(file + ":" + line0 + ": syntax error, expression is not a statement near '" + Peek.Text + "'");
    }

    void SkipType()
    {
        if (Accept(":"))
        {
            // very small type skipper: Name{.Name}[<...>][?]
            ExpectName("in type annotation");
            while (Accept(".")) ExpectName("in type annotation");
            Accept("?");
        }
    }

    void FuncBody(bool method)
    {
        Expect("(", "to start parameter list");
        Push();
        if (method) Declare("self");
        if (!Is(")"))
        {
            do
            {
                if (Accept("...")) break;
                Declare(ExpectName("in parameter list"));
                SkipType();
            } while (Accept(","));
        }
        Expect(")", "to close parameter list");
        int line = Peek.Line;
        Block();
        Pop();
        Expect("end", "to close function (line " + line + ")");
    }

    void ExpList()
    {
        do { Expr(); } while (Accept(","));
    }

    static readonly Dictionary<string, int[]> Binary = new Dictionary<string, int[]> {
        {"or", new[]{1,1}}, {"and", new[]{2,2}},
        {"<", new[]{3,3}}, {">", new[]{3,3}}, {"<=", new[]{3,3}}, {">=", new[]{3,3}}, {"~=", new[]{3,3}}, {"==", new[]{3,3}},
        {"..", new[]{5,4}}, {"+", new[]{6,6}}, {"-", new[]{6,6}},
        {"*", new[]{7,7}}, {"/", new[]{7,7}}, {"//", new[]{7,7}}, {"%", new[]{7,7}}, {"^", new[]{10,9}},
    };
    const int UnaryPri = 8;

    void Expr() { SubExpr(0); }

    void SubExpr(int limit)
    {
        if (Is("not") || Is("-") || Is("#")) { Next(); SubExpr(UnaryPri); }
        else SimpleExpr();
        while (true)
        {
            var t = Peek;
            int[] pri;
            if ((t.Kind == K.Symbol || t.Kind == K.Keyword) && Binary.TryGetValue(t.Text, out pri) && pri[0] > limit)
            {
                Next();
                SubExpr(pri[1]);
            }
            else break;
        }
    }

    void SimpleExpr()
    {
        var t = Peek;
        if (t.Kind == K.Number || t.Kind == K.String) { Next(); return; }
        if (t.Kind == K.Keyword)
        {
            if (t.Text == "nil" || t.Text == "true" || t.Text == "false") { Next(); return; }
            if (t.Text == "function") { Next(); FuncBody(false); return; }
            if (t.Text == "if")
            {
                Next(); Expr(); Expect("then", "in if-expression"); Expr();
                while (Accept("elseif")) { Expr(); Expect("then", "in if-expression"); Expr(); }
                Expect("else", "in if-expression"); Expr();
                return;
            }
        }
        if (Is("...")) { Next(); return; }
        if (Is("{")) { Table(); return; }
        bool c; string r;
        SuffixedExpr(out c, out r, false);
    }

    void Table()
    {
        Expect("{", "");
        while (!Is("}"))
        {
            if (Is("["))
            {
                Next(); Expr(); Expect("]", "in table key"); Expect("=", "after table key"); Expr();
            }
            else if (Peek.Kind == K.Name && PeekAt(1).Text == "=" && PeekAt(1).Kind == K.Symbol)
            {
                Next(); Next(); Expr();
            }
            else Expr();
            if (!Accept(",") && !Accept(";")) break;
        }
        Expect("}", "to close table");
    }

    void SuffixedExpr(out bool isCall, out string rootName, bool statement)
    {
        isCall = false;
        rootName = null;
        var t = Peek;
        if (t.Kind == K.Name)
        {
            Next();
            rootName = t.Text;
            Use(t.Text, t.Line);
        }
        else if (Accept("("))
        {
            Expr();
            Expect(")", "to close parenthesis");
        }
        else throw new ParseError(file + ":" + t.Line + ": unexpected '" + t.Text + "'");
        while (true)
        {
            if (Accept(".")) { ExpectName("after '.'"); isCall = false; }
            else if (Is("[")) { Next(); Expr(); Expect("]", "to close index"); isCall = false; }
            else if (Accept(":")) { ExpectName("after ':'"); Args(); isCall = true; }
            else if (Is("(") || Is("{") || Peek.Kind == K.String)
            {
                // a '(' on a new line after a complete statement is ambiguous in Lua; treat as call
                Args();
                isCall = true;
            }
            else break;
        }
    }

    void Args()
    {
        if (Peek.Kind == K.String) { Next(); return; }
        if (Is("{")) { Table(); return; }
        Expect("(", "for call arguments");
        if (!Is(")")) ExpList();
        Expect(")", "to close call arguments");
    }

    public static List<string> Check(string path, string display)
    {
        var chk = new LuaCheck();
        chk.file = display;
        var src = File.ReadAllText(path, Encoding.UTF8);
        chk.toks = Lex(src, display, chk.Problems);
        chk.Push();
        try
        {
            chk.Block();
            if (chk.Peek.Kind != K.EOF)
                chk.Problems.Add(display + ":" + chk.Peek.Line + ": unexpected '" + chk.Peek.Text + "' (extra 'end'?)");
        }
        catch (ParseError e)
        {
            chk.Problems.Add(e.Message);
        }
        return chk.Problems;
    }
}
