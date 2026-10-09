// skinflint hooks for Windows, compiled on first use by the csc.exe that
// ships with the .NET Framework. Implements SPEC.md, the same contract as
// hooks/lib/skinflint.awk, and must produce the same bytes.
//
// Text is held as "byte strings": UTF-8 input decoded as Latin-1, so one char
// is one byte. Lengths, cuts and regexes then work on bytes exactly as the awk
// side does under LC_ALL=C. In regexes \z stands for awk's $, because .NET's $
// also matches before a final newline.
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace Skinflint {

class Node {
  public char T;                       // o a s n t f z
  public string V;                     // decoded string, number token
  public List<string> K = new List<string>();
  public List<Node> C = new List<Node>();
  public int B, E;                     // span in the parsed text, inclusive
  public bool Dup;                     // an object repeats a key
}

public static class Hook {
  // Byte strings by hand: looking up the Latin-1 Encoding costs startup time.
  static string L1(byte[] b) { char[] c = new char[b.Length]; for (int i = 0; i < b.Length; i++) c[i] = (char)b[i]; return new string(c); }
  static byte[] L1(string s) { byte[] b = new byte[s.Length]; for (int i = 0; i < s.Length; i++) b[i] = (byte)s[i]; return b; }
  const string UP = "SKINFLINT";
  const string CHECK = "\xE2\x9C\x93";
  // Regexes are built on first use: a hook needs only a few of them, and
  // building all of them up front costs milliseconds on every call.

  static string Payload, State, Sess, SpillDir, ClaudeDir, Plugin, Mode, Sid;
  static string CfgMode = "", Tool, SafeTool, Tuid;
  static int CfgProse = -1, CfgCode = -1, Max, Head, Tail, NS;
  static bool Prose, Code, View, CanWrite, CanSpill, Spilled, RChanged;
  static string Rescue;
  static Node Root;
  static readonly List<Node> Slot = new List<Node>();
  static readonly Dictionary<Node, string> NewOf = new Dictionary<Node, string>();
  static readonly Dictionary<Node, bool> Holds = new Dictionary<Node, bool>();
  static string[] LN;
  static void HoldsAdd(Node n) { Holds[n] = true; }

  public static int Main(string[] args) {
    try {
      string o = Run(args.Length > 0 ? args[0] : "");
      if (o.Length > 0) {
        byte[] b = L1(o);
        Stream so = Console.OpenStandardOutput();
        so.Write(b, 0, b.Length);
        so.Flush();
      }
    } catch (Exception e) {
      if (Env("SKINFLINT_DEBUG") == "1") Console.Error.WriteLine(e);
    }
    return 0;
  }

  static string Env(string k) { return Environment.GetEnvironmentVariable(k) ?? ""; }

  static string Run(string hook) {
    MemoryStream ms = new MemoryStream();
    Console.OpenStandardInput().CopyTo(ms);
    byte[] raw = ms.ToArray();
    if (!ValidUtf8(raw, 0)) return "";
    Payload = L1(raw);
    Root = Parse(Payload);
    if (Root == null || Root.T != 'o') return "";
    Setup();
    LoadConfig();
    LoadSession();
    if (hook == "activate") return Activate();
    if (hook == "prompt") return Prompt();
    if (hook == "subagent") return Subagent();
    if (hook == "compress") return Compress();
    if (hook == "stop") return Stop();
    return "";
  }

  // ---------- paths and files (2) ----------

  // Paths are built with /, which every Windows file API accepts, so the
  // paths this prints read the same as on the POSIX side (8).
  static string Slash(string d) { return d.Replace('\\', '/'); }

  static string Strip(string d) {
    d = Slash(d);
    while (d.Length > 1 && d.EndsWith("/")) {
      if (d.Length == 3 && d[1] == ':') break;
      d = d.Substring(0, d.Length - 1);
    }
    return d;
  }

  static void Setup() {
    string d = Env("CLAUDE_CONFIG_DIR");
    if (d == "") d = Env("USERPROFILE") + "/.claude";
    ClaudeDir = Strip(d);
    State = ClaudeDir + "/skinflint";
    Sess = State + "/sessions"; SpillDir = State + "/spill";
    Plugin = Strip(Env("CLAUDE_PLUGIN_ROOT"));
    try { Directory.CreateDirectory(Sess); Directory.CreateDirectory(SpillDir); } catch { }
    CanWrite = Directory.Exists(Sess);
    CanSpill = Directory.Exists(SpillDir);
  }

  // Whole file as a byte string, or null when it is not a readable file.
  static string ReadFile(string p) {
    try { return File.Exists(p) ? L1(File.ReadAllBytes(p)) : null; } catch { return null; }
  }

  static bool WriteFile(string p, string data) {
    try { File.WriteAllBytes(p, L1(data)); return true; } catch { return false; }
  }

  static string NoBom(string s) { return s.StartsWith("\xEF\xBB\xBF", StringComparison.Ordinal) ? s.Substring(3) : s; }

  static bool ValidUtf8(byte[] b, int start) {
    int i = start, n = b.Length;
    while (i < n) {
      int c = b[i];
      if (c < 0x80) { i++; continue; }
      int need, lo = 0x80, hi = 0xBF;
      if (c >= 0xC2 && c <= 0xDF) need = 1;
      else if (c == 0xE0) { need = 2; lo = 0xA0; }
      else if (c >= 0xE1 && c <= 0xEF) { need = 2; if (c == 0xED) hi = 0x9F; }
      else if (c == 0xF0) { need = 3; lo = 0x90; }
      else if (c >= 0xF1 && c <= 0xF3) need = 3;
      else if (c == 0xF4) { need = 3; hi = 0x8F; }
      else return false;
      for (int j = 1; j <= need; j++) {
        if (i + j >= n) return false;
        int x = b[i + j];
        if (x < lo || x > hi) return false;
        lo = 0x80; hi = 0xBF;
      }
      i += need + 1;
    }
    return true;
  }

  static bool ValidUtf8(string s) { return ValidUtf8(L1(s), 0); }

  // ---------- JSON (1) ----------

  static string PS; static int PP; static bool PErr;

  static Node Parse(string s) {
    PS = s; PP = 0; PErr = false;
    Ws();
    Node n = Value();
    if (PErr || n == null) return null;
    Ws();
    return PP < PS.Length ? null : n;
  }

  static void Ws() {
    while (PP < PS.Length) {
      char c = PS[PP];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') PP++; else break;
    }
  }

  static Regex _NumRe; static Regex NumRe { get { return _NumRe ?? (_NumRe = new Regex(@"\G-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?", RegexOptions.CultureInvariant)); } }

  static Node Value() {
    if (PP >= PS.Length) { PErr = true; return null; }
    char c = PS[PP];
    Node n = new Node(); n.B = PP;
    if (c == '{') {
      n.T = 'o'; PP++; Ws();
      if (PP < PS.Length && PS[PP] == '}') { PP++; n.E = PP - 1; return n; }
      while (true) {
        Ws();
        if (PP >= PS.Length || PS[PP] != '"') { PErr = true; return null; }
        string k = Str(); if (PErr) return null;
        Ws();
        if (PP >= PS.Length || PS[PP] != ':') { PErr = true; return null; }
        PP++; Ws();
        Node v = Value(); if (PErr) return null;
        if (n.K.Contains(k)) n.Dup = true;
        n.K.Add(k); n.C.Add(v);
        Ws();
        if (PP >= PS.Length) { PErr = true; return null; }
        if (PS[PP] == ',') { PP++; continue; }
        if (PS[PP] == '}') { PP++; n.E = PP - 1; return n; }
        PErr = true; return null;
      }
    }
    if (c == '[') {
      n.T = 'a'; PP++; Ws();
      if (PP < PS.Length && PS[PP] == ']') { PP++; n.E = PP - 1; return n; }
      while (true) {
        Ws();
        Node v = Value(); if (PErr) return null;
        n.C.Add(v);
        Ws();
        if (PP >= PS.Length) { PErr = true; return null; }
        if (PS[PP] == ',') { PP++; continue; }
        if (PS[PP] == ']') { PP++; n.E = PP - 1; return n; }
        PErr = true; return null;
      }
    }
    if (c == '"') { n.T = 's'; n.V = Str(); n.E = PP - 1; return PErr ? null : n; }
    if (string.CompareOrdinal(PS, PP, "true", 0, 4) == 0) { n.T = 't'; PP += 4; n.E = PP - 1; return n; }
    if (string.CompareOrdinal(PS, PP, "false", 0, 5) == 0) { n.T = 'f'; PP += 5; n.E = PP - 1; return n; }
    if (string.CompareOrdinal(PS, PP, "null", 0, 4) == 0) { n.T = 'z'; PP += 4; n.E = PP - 1; return n; }
    Match m = NumRe.Match(PS, PP);
    if (m.Success && m.Length > 0) { n.T = 'n'; n.V = m.Value; PP += m.Length; n.E = PP - 1; return n; }
    PErr = true; return null;
  }

  static int Hex(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  }

  static int Hex4(int at) {
    if (at + 4 > PS.Length) return -1;
    int v = 0;
    for (int i = 0; i < 4; i++) { int h = Hex(PS[at + i]); if (h < 0) return -1; v = v * 16 + h; }
    return v;
  }

  static void Utf8(StringBuilder sb, int cp) {
    if (cp >= 0xD800 && cp <= 0xDFFF) { sb.Append("\xEF\xBF\xBD"); return; }
    if (cp < 0x80) sb.Append((char)cp);
    else if (cp < 0x800) { sb.Append((char)(0xC0 | cp >> 6)); sb.Append((char)(0x80 | cp & 63)); }
    else if (cp < 0x10000) { sb.Append((char)(0xE0 | cp >> 12)); sb.Append((char)(0x80 | cp >> 6 & 63)); sb.Append((char)(0x80 | cp & 63)); }
    else { sb.Append((char)(0xF0 | cp >> 18)); sb.Append((char)(0x80 | cp >> 12 & 63)); sb.Append((char)(0x80 | cp >> 6 & 63)); sb.Append((char)(0x80 | cp & 63)); }
  }

  // At an opening quote: the decoded string; PP moves past the closing quote.
  static string Str() {
    PP++;
    int start = PP;
    while (PP < PS.Length && PS[PP] != '"' && PS[PP] != '\\' && PS[PP] >= 0x20) PP++;
    if (PP < PS.Length && PS[PP] == '"') { string r = PS.Substring(start, PP - start); PP++; return r; }
    StringBuilder sb = new StringBuilder(PS, start, PP - start, (PP - start) * 2 + 16);
    while (true) {
      if (PP >= PS.Length) { PErr = true; return ""; }
      char c = PS[PP];
      if (c == '"') { PP++; return sb.ToString(); }
      if (c < 0x20) { PErr = true; return ""; }
      if (c != '\\') { sb.Append(c); PP++; continue; }
      if (PP + 1 >= PS.Length) { PErr = true; return ""; }
      char e = PS[PP + 1];
      PP += 2;
      switch (e) {
        case '"': sb.Append('"'); break;
        case '\\': sb.Append('\\'); break;
        case '/': sb.Append('/'); break;
        case 'b': sb.Append('\b'); break;
        case 'f': sb.Append('\f'); break;
        case 'n': sb.Append('\n'); break;
        case 'r': sb.Append('\r'); break;
        case 't': sb.Append('\t'); break;
        case 'u':
          int cp = Hex4(PP);
          if (cp < 0) { PErr = true; return ""; }
          PP += 4;
          if (cp >= 0xD800 && cp <= 0xDBFF && PP + 1 < PS.Length && PS[PP] == '\\' && PS[PP + 1] == 'u') {
            int nx = Hex4(PP + 2);
            if (nx >= 0xDC00 && nx <= 0xDFFF) { Utf8(sb, 0x10000 + (cp - 0xD800) * 1024 + (nx - 0xDC00)); PP += 6; break; }
          }
          Utf8(sb, cp);
          break;
        default: PErr = true; return "";
      }
    }
  }

  // Last occurrence wins (1).
  static Node Get(Node o, string k) {
    if (o == null || o.T != 'o') return null;
    for (int i = o.K.Count - 1; i >= 0; i--) if (o.K[i] == k) return o.C[i];
    return null;
  }

  static string JStr(Node o, string k) { Node v = Get(o, k); return v != null && v.T == 's' ? v.V : ""; }
  static bool JBool(Node o, string k) { Node v = Get(o, k); return v != null && v.T == 't'; }

  static string JsonStr(string s) {
    StringBuilder sb = new StringBuilder(s.Length + 16);
    sb.Append('"');
    foreach (char c in s) {
      switch (c) {
        case '"': sb.Append("\\\""); break;
        case '\\': sb.Append("\\\\"); break;
        case '\n': sb.Append("\\n"); break;
        case '\r': sb.Append("\\r"); break;
        case '\t': sb.Append("\\t"); break;
        case '\b': sb.Append("\\b"); break;
        case '\f': sb.Append("\\f"); break;
        default:
          if (c < 0x20) sb.Append("\\u00").Append(((int)c).ToString("x2")); else sb.Append(c);
          break;
      }
    }
    sb.Append('"');
    return sb.ToString();
  }

  static string Ctx(string ev, string text) {
    AddStats(0, 0, 0, 0, text.Length);
    return "{\"hookSpecificOutput\":{\"hookEventName\":\"" + ev + "\",\"additionalContext\":" + JsonStr(text) + "}}";
  }

  // ---------- text helpers (1) ----------

  static bool IsWs(char c) { return c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\v' || c == '\f'; }

  static string Trim(string s) {
    int a = 0, b = s.Length;
    while (a < b && IsWs(s[a])) a++;
    while (b > a && IsWs(s[b - 1])) b--;
    return s.Substring(a, b - a);
  }

  static string Lower(string s) {
    char[] a = s.ToCharArray();
    for (int i = 0; i < a.Length; i++) if (a[i] >= 'A' && a[i] <= 'Z') a[i] = (char)(a[i] + 32);
    return new string(a);
  }

  static bool IsCont(char c) { return c >= 0x80 && c <= 0xBF; }

  static string HeadBytes(string s, int n) {
    if (n >= s.Length) return s;
    while (n > 0 && IsCont(s[n])) n--;
    return s.Substring(0, n);
  }

  static string TailBytes(string s, int n) {
    if (n >= s.Length) return s;
    int st = s.Length - n;
    while (st < s.Length && IsCont(s[st])) st++;
    return s.Substring(st);
  }

  static string Cut300(string l) { return l.Length > 300 ? HeadBytes(l, 300) + "..." : l; }

  static int Num(string k, int fb) {
    string v = Env("SKINFLINT_" + k);
    if (v.Length == 0 || v.Length > 9) return fb;
    foreach (char c in v) if (c < '0' || c > '9') return fb;
    int n = int.Parse(v);
    return n > 0 ? n : fb;
  }

  static string[] Lines(string t) { return t.Split('\n'); }

  static string Safe(string s) {
    StringBuilder sb = new StringBuilder();
    foreach (char c in s) if (c >= 'A' && c <= 'Z' || c >= 'a' && c <= 'z' || c >= '0' && c <= '9' || c == '_' || c == '-') sb.Append(c);
    return sb.ToString();
  }

  // ---------- config, mode, sections (2, 3) ----------

  // The user config, then the project's .claude/skinflint.json: a valid key
  // in the project file replaces the user's value for that key.
  static void LoadConfig() {
    string dir = Env("XDG_CONFIG_HOME");
    ConfigFile((dir != "" ? Strip(dir) : Slash(Env("APPDATA"))) + "/skinflint/config.json");
    ConfigFile(".claude/skinflint.json");
  }

  static void ConfigFile(string p) {
    string raw = ReadFile(p);
    if (string.IsNullOrEmpty(raw)) return;
    raw = NoBom(raw);
    if (!ValidUtf8(raw)) return;
    Node id = Parse(raw);
    if (id == null || id.T != 'o') return;
    string m = Lower(JStr(id, "defaultMode"));
    if (m == "on" || m == "off") CfgMode = m;
    Node s = Get(id, "sections");
    if (s != null && s.T == 'o') {
      Node v = Get(s, "prose"); if (v != null && (v.T == 't' || v.T == 'f')) CfgProse = v.T == 't' ? 1 : 0;
      v = Get(s, "code"); if (v != null && (v.T == 't' || v.T == 'f')) CfgCode = v.T == 't' ? 1 : 0;
    }
  }

  static string DefaultMode() {
    string e = Lower(Env("SKINFLINT_DEFAULT_MODE"));
    if (e == "on" || e == "off") return e;
    return CfgMode != "" ? CfgMode : "on";
  }


  static void LoadSession() {
    Sid = JStr(Root, "session_id");
    if (Sid.Length == 0 || Sid.Length > 128 || Safe(Sid) != Sid) Sid = "";
    Mode = DefaultMode();
    if (Sid == "") return;
    string m = Lower(Trim(ReadFile(Sess + "/" + Sid + ".mode") ?? ""));
    if (m == "on" || m == "off") Mode = m;
  }

  static void Sections() {
    Prose = true; Code = true;
    if (CfgProse >= 0) Prose = CfgProse == 1;
    if (CfgCode >= 0) Code = CfgCode == 1;
    if (CfgProse >= 0) return;
    string[] ps = { ".claude/settings.local.json", ".claude/settings.json", ClaudeDir + "/settings.json" };
    foreach (string p in ps) {
      string raw = ReadFile(p);
      if (raw == null) continue;
      raw = NoBom(raw);
      if (raw.IndexOf("\"outputStyle\"", StringComparison.Ordinal) < 0 || !ValidUtf8(raw)) continue;
      Node id = Parse(raw);
      if (id == null || id.T != 'o') continue;
      Node v = Get(id, "outputStyle");
      if (v == null || v.T != 's') continue;
      string st = Trim(v.V);
      if (st == "") continue;
      if (Lower(st) != "default") Prose = false;
      return;
    }
  }

  static string Reminder() {
    Sections();
    string s = UP + " ON.";
    if (Prose) s += " Prose: answer first, then only what the user needs to act; a question with one answer gets one or two sentences; for a problem, the likely cause and its fix, not every possibility; for a comparison, the pick first, then at most three one-sentence reasons; sentences, no headings or bullet lists (number steps only when they run in order).";
    if (Code) s += " Code: smallest change that works, reuse before writing, nothing speculative; the code first, then one line only if the user must change something to use it; no alternatives, demos or tests unless asked; when asked to write or show code, reply with it and create no file unless the user named one.";
    return s + " Code, commit messages and security warnings stay in full sentences. Apply these rules at once, without weighing them.";
  }

  // ---------- SessionStart (5.1) ----------

  static string Activate() {
    string src = JStr(Root, "source");
    if (src == "startup") PruneSessions();
    if (Mode == "off") return "";
    return Ctx("SessionStart", Reminder());
  }

  static void PruneSessions() {
    try {
      DateTime now = DateTime.UtcNow;
      foreach (FileInfo f in new DirectoryInfo(Sess).GetFiles())
        if (Math.Floor((now - f.LastWriteTimeUtc).TotalDays) > 7) try { f.Delete(); } catch { }
    } catch { }
  }

  // ---------- UserPromptSubmit (5.2) ----------

  static readonly string[] OffForms = { "stop skinflint", "skinflint off", "skinflint mode off", "/skinflint off",
    "disable skinflint", "turn off skinflint", "deactivate skinflint", "normal mode" };
  static readonly string[] OnForms = { "/skinflint", "/skinflint on", "skinflint on", "skinflint mode",
    "skinflint mode on", "start skinflint", "enable skinflint", "turn on skinflint", "activate skinflint", "use skinflint" };

  static string Prompt() {
    string c = CommandForm(JStr(Root, "prompt"));
    string want = Array.IndexOf(OffForms, c) >= 0 ? "off" : Array.IndexOf(OnForms, c) >= 0 ? "on" : "";
    if (want != "") {
      if (Sid != "" && CanWrite) WriteFile(Sess + "/" + Sid + ".mode", want);
      Mode = want;
    }
    if (want == "on") return Ctx("UserPromptSubmit", Reminder());
    if (Mode == "on") return Ctx("UserPromptSubmit", UP + " ON.");
    if (want == "off") return Ctx("UserPromptSubmit", UP + " OFF. Write normally until the user turns it back on.");
    return "";
  }

  static string CommandForm(string p) {
    p = Trim(Lower(p));
    if (p.Length >= 2 && p[0] == p[p.Length - 1] && (p[0] == '`' || p[0] == '"' || p[0] == '\'')) p = Trim(p.Substring(1, p.Length - 2));
    if (p.Length > 0 && (p[p.Length - 1] == '.' || p[p.Length - 1] == '!')) p = Trim(p.Substring(0, p.Length - 1));
    StringBuilder sb = new StringBuilder(p.Length);
    for (int i = 0; i < p.Length; i++) {
      if (!IsWs(p[i])) { sb.Append(p[i]); continue; }
      sb.Append(' ');
      while (i + 1 < p.Length && IsWs(p[i + 1])) i++;
    }
    p = sb.ToString();
    return p.Replace("skin flint", "skinflint").Replace("skin-flint", "skinflint");
  }

  // ---------- SubagentStart (5.3) ----------

  static string Subagent() {
    return Mode == "on" ? Ctx("SubagentStart", Reminder() + " You are a subagent: write your final report the same way.") : "";
  }

  // ---------- Stop (5.4) ----------

  static string Stop() {
    if (Mode != "on") return "";
    string m = JStr(Root, "last_assistant_message");
    if (m != "") AddStats(0, 0, m.Length, 1, 0);
    return "";
  }

  // ---------- PostToolUse (4) ----------

  static string Compress() {
    if (Mode != "on" || Env("SKINFLINT_COMPRESS") == "0") return "";
    string tool = JStr(Root, "tool_name");
    if (!ToolOk(tool)) return "";
    Node resp = Get(Root, "tool_response");
    if (resp == null || resp.T == 'z') return "";
    if (resp.T == 'o' && (JBool(resp, "isImage") || JBool(resp, "interrupted") || Get(resp, "persistedOutputPath") != null)) return "";
    Node ti = Get(Root, "tool_input");
    if (ti != null && ti.T == 'o')
      foreach (Node v in ti.C)
        if (v.T == 's' && (v.V.IndexOf("skinflint/spill", StringComparison.Ordinal) >= 0 || v.V.IndexOf("skinflint\\spill", StringComparison.Ordinal) >= 0)) return "";
    if (!FindSlots(resp) || Slot.Count == 0) return "";
    NS = Slot.Count;

    Tool = tool; SafeTool = Safe(tool); if (SafeTool == "") SafeTool = "tool";
    Tuid = Safe(JStr(Root, "tool_use_id"));
    Max = Num("MAX_BYTES", 8000); Head = Num("HEAD_LINES", 60); Tail = Num("TAIL_LINES", 40);
    // U+0000 is removed first: Windows tools that write UTF-16 arrive with a
    // NUL after every ASCII character. Each counts as one saved byte.
    long nuls = 0;
    foreach (Node sl in Slot)
      if (sl.V.IndexOf('\0') >= 0) { string v = sl.V.Replace("\0", ""); nuls += sl.V.Length - v.Length; sl.V = v; }
    bool big = false;
    foreach (Node sl in Slot) if (sl.V.Length > 1024) big = true;
    View = big && (tool == "Bash" || tool == "PowerShell") && ti != null && ti.T == 'o' && IsView(JStr(ti, "command"));

    string[] old = new string[NS], nw = new string[NS];
    for (int k = 0; k < NS; k++) { old[k] = Slot[k].V; nw[k] = old[k]; }
    string unit = string.Join("\x1e", old);
    if (!Dedup(unit, nw)) for (int k = 0; k < NS; k++) nw[k] = Pipeline(old[k], k + 1);
    long saved = nuls;
    for (int k = 0; k < NS; k++) saved += old[k].Length - nw[k].Length;
    string outp = "";
    if (saved >= 64) {
      for (int k = 0; k < NS; k++) NewOf[Slot[k]] = nw[k];
      outp = "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"updatedToolOutput\":" + Emit(resp) + "}}";
      AddStats(saved, 1, 0, 0, 0);
    }
    if (Spilled) PruneSpill();
    return outp;
  }

  static bool ToolOk(string t) {
    if (t == "" || t == "Read" || t == "Edit" || t == "Write" || t == "MultiEdit" || t == "NotebookEdit" || t == "NotebookRead") return false;
    string list = Env("SKINFLINT_TOOLS");
    if (list != "") {
      foreach (string x in list.Split(',')) if (Trim(x) == t) return true;
      return false;
    }
    if (t == "Bash" || t == "PowerShell" || t == "Agent" || t == "WebFetch" || t == "WebSearch" || t == "Grep" || t == "Glob") return true;
    return t.StartsWith("mcp__", StringComparison.Ordinal);
  }

  static bool FindSlots(Node id) {
    if (id.T == 's') { Slot.Add(id); return true; }
    if (id.T == 'a') return FindBlocks(id);
    if (id.T != 'o') return true;
    for (int i = 0; i < id.K.Count; i++) {
      Node c = id.C[i]; string k = id.K[i];
      if (c.T == 's' && (k == "stdout" || k == "stderr" || k == "output" || k == "content" || k == "text" || k == "result")) { Slot.Add(c); HoldsAdd(id); }
      else if (c.T == 'a' && k == "content") { if (!FindBlocks(c)) return false; if (Holds.ContainsKey(c)) HoldsAdd(id); }
    }
    return !(Holds.ContainsKey(id) && id.Dup);
  }

  static bool FindBlocks(Node arr) {
    foreach (Node b in arr.C) {
      if (b.T != 'o') continue;
      Node t = Get(b, "type");
      if (t == null || t.T != 's' || t.V != "text") continue;
      for (int j = 0; j < b.K.Count; j++)
        if (b.K[j] == "text" && b.C[j].T == 's') { Slot.Add(b.C[j]); HoldsAdd(b); }
      if (Holds.ContainsKey(b) && b.Dup) return false;
      if (Holds.ContainsKey(b)) HoldsAdd(arr);
    }
    return true;
  }

  // Rebuild (4.6).
  static string Emit(Node id) {
    string nv;
    if (NewOf.TryGetValue(id, out nv)) return JsonStr(nv);
    if (!Holds.ContainsKey(id)) return Payload.Substring(id.B, id.E - id.B + 1);
    StringBuilder sb = new StringBuilder();
    if (id.T == 'a') {
      sb.Append('[');
      for (int i = 0; i < id.C.Count; i++) { if (i > 0) sb.Append(','); sb.Append(Emit(id.C[i])); }
      return sb.Append(']').ToString();
    }
    sb.Append('{');
    for (int i = 0; i < id.C.Count; i++) { if (i > 0) sb.Append(','); sb.Append(JsonStr(id.K[i])).Append(':').Append(Emit(id.C[i])); }
    return sb.Append('}').ToString();
  }

  static Regex _Word; static Regex Word { get { return _Word ?? (_Word = new Regex(@"\G[^ \t\n\r\v\f]+", RegexOptions.CultureInvariant)); } }
  static Regex _Assign; static Regex Assign { get { return _Assign ?? (_Assign = new Regex(@"^[A-Za-z_][A-Za-z0-9_]*=", RegexOptions.CultureInvariant)); } }
  static Regex _ViewCmd; static Regex ViewCmd { get { return _ViewCmd ?? (_ViewCmd = new Regex(@"^(cat|head|tail|sed|nl|less|more|bat|batcat|diff|jq|xxd|od|get-content|gc|type)\z", RegexOptions.CultureInvariant)); } }
  static Regex _GitView; static Regex GitView { get { return _GitView ?? (_GitView = new Regex(@"\G(show|diff|cat-file)([ \t\n\r\v\f]|\z)", RegexOptions.CultureInvariant)); } }

  static bool IsView(string cmd) {
    if (cmd.IndexOf('|') >= 0) return false;
    int p = 0; string w;
    while (true) {
      while (p < cmd.Length && IsWs(cmd[p])) p++;
      Match m = Word.Match(cmd, p);
      if (!m.Success) return false;
      w = m.Value; p += w.Length;
      if (Assign.IsMatch(w)) continue;
      break;
    }
    if (w == "sudo") {
      while (p < cmd.Length && IsWs(cmd[p])) p++;
      Match m = Word.Match(cmd, p);
      if (!m.Success) return false;
      w = m.Value; p += w.Length;
    }
    if (ViewCmd.IsMatch(Lower(w))) return true;
    if (w != "git") return false;
    while (p < cmd.Length && IsWs(cmd[p])) p++;
    return GitView.IsMatch(cmd, p);
  }

  // ---------- dedup (4.5) ----------

  static bool Dedup(string unit, string[] nw) {
    if (Env("SKINFLINT_DEDUP") == "0" || Sid == "" || Tuid == "") return false;
    if (unit.Length < 2048 || unit.Length > 1048576) return false;
    string p = Sess + "/" + Sid + "." + SafeTool + ".last";
    string raw = ReadFile(p) ?? "";
    int nl = raw.IndexOf('\n');
    bool dup = nl >= 0 && raw.Substring(0, nl) != Tuid && raw.Substring(nl + 1) == unit;
    if (CanWrite) WriteFile(p, Tuid + "\n" + unit);
    if (!dup) return false;
    string[] L = Lines(unit);
    int k = Math.Min(L.Length, 5);
    string[] first = new string[k];
    for (int i = 0; i < k; i++) first[i] = Cut300(L[i]);
    nw[0] = "[skinflint: same output as the previous " + Tool + " call (" + unit.Length + " bytes, " + L.Length + " lines). It starts:]\n" + string.Join("\n", first);
    for (int i = 1; i < nw.Length; i++) nw[i] = "";
    return true;
  }

  // ---------- per-slot pipeline (4.2) ----------

  static string Pipeline(string t, int slot) {
    if (t.Length <= 1024) return t;
    if (View) {
      if (t.Length <= Max + Max / 2) return t;
      LN = Lines(t);
      return LN.Length > Head + Tail ? CutLines(t, t, slot, LN.Length) : CutBytes(t, t, slot);
    }
    string orig = t;
    t = Clean(t);
    LN = Lines(t);
    int n = Repeats(LN.Length);
    if (RChanged) t = string.Join("\n", LN, 0, n);
    if (t.Length > Max && n > Head + Tail) return CutLines(t, orig, slot, n);
    t = Finer(t);
    if (t.Length > Max) t = CutBytes(t, orig, slot);
    return t;
  }

  const RegexOptions O = RegexOptions.CultureInvariant;
  static Regex _Csi; static Regex Csi { get { return _Csi ?? (_Csi = new Regex(@"\x1b\[[0-9;?]*[ -/]*[@-~]", O)); } }
  static Regex _Osc; static Regex Osc { get { return _Osc ?? (_Osc = new Regex(@"\x1b\][^\x07\x1b\n]*(\x07|\x1b\\)", O)); } }
  static Regex _CrInside; static Regex CrInside { get { return _CrInside ?? (_CrInside = new Regex(@"\r[^\n]", O)); } }
  static Regex _TrailPre; static Regex TrailPre { get { return _TrailPre ?? (_TrailPre = new Regex(@"[ \t](\r?\n|\r?\z)", O)); } }
  static Regex _TrailWs; static Regex TrailWs { get { return _TrailWs ?? (_TrailWs = new Regex(@"[ \t]+\n", O)); } }
  static Regex _TrailWsCr; static Regex TrailWsCr { get { return _TrailWsCr ?? (_TrailWsCr = new Regex(@"[ \t]+\r\n", O)); } }
  static Regex _TrailEnd; static Regex TrailEnd { get { return _TrailEnd ?? (_TrailEnd = new Regex(@"[ \t]+\z", O)); } }
  static Regex _TrailEndCr; static Regex TrailEndCr { get { return _TrailEndCr ?? (_TrailEndCr = new Regex(@"[ \t]+\r\z", O)); } }
  static Regex _Blank; static Regex Blank { get { return _Blank ?? (_Blank = new Regex(@"\n\n\n+", O)); } }

  static string Clean(string t) {
    if (t.IndexOf('\x1b') >= 0) { t = Csi.Replace(t, ""); t = Osc.Replace(t, ""); }
    if (CrInside.IsMatch(t)) {
      string[] L = Lines(t);
      for (int i = 0; i < L.Length; i++) {
        string body = L[i], cr = "";
        if (body.Length > 0 && body[body.Length - 1] == '\r') { cr = "\r"; body = body.Substring(0, body.Length - 1); }
        int r = body.LastIndexOf('\r');
        if (r >= 0) body = body.Substring(r + 1);
        L[i] = body + cr;
      }
      t = string.Join("\n", L);
    }
    if (TrailPre.IsMatch(t)) {
      t = TrailWs.Replace(t, "\n");
      if (t.IndexOf('\r') >= 0) t = TrailWsCr.Replace(t, "\r\n");
      t = TrailEnd.Replace(t, "", 1);
      t = TrailEndCr.Replace(t, "\r", 1);
    }
    if (t.IndexOf("\n\n\n", StringComparison.Ordinal) >= 0) t = Blank.Replace(t, "\n\n");
    return t;
  }

  static int Repeats(int n) {
    RChanged = false;
    int k = 0;
    for (int i = 0, j; i < n; i = j) {
      string cur = LN[i];
      for (j = i + 1; j < n && LN[j] == cur; j++) { }
      int r = j - i;
      if (r >= 3 && cur != "") { LN[k++] = cur; LN[k++] = "[skinflint: line above repeated " + (r - 1) + " more times]"; RChanged = true; }
      else while (i < j) LN[k++] = LN[i++];
    }
    return k;
  }

  static Regex _HasClock; static Regex HasClock { get { return _HasClock ?? (_HasClock = new Regex(@"[0-9][0-9]:[0-9][0-9]:[0-9][0-9]", O)); } }
  static Regex _HasFrame; static Regex HasFrame { get { return _HasFrame ?? (_HasFrame = new Regex(@"(^|\n)([ \t]+at [^ \t]|[ \t]*#[0-9]+[ \t]|[ \t]+File "")", O)); } }
  static Regex _HasPass; static Regex HasPass { get { return _HasPass ?? (_HasPass = new Regex(@"(^|\n)(ok|PASS|PASSED)([ \t:]|\n|\z)|[ \t](ok|PASS|PASSED)(\n|\z)|(^|\n)[ \t]*(PASS|PASSED)[ \t]", O)); } }

  static string Finer(string t) {
    if (HasClock.IsMatch(t)) t = Stamps(t);
    if (HasFrame.IsMatch(t)) t = Frames(t);
    if (HasPass.IsMatch(t) || t.IndexOf(CHECK, StringComparison.Ordinal) >= 0) t = Passes(t);
    if (t.Length > 4096) t = LongLines(t);
    return t;
  }

  static Regex _Stamp; static Regex Stamp { get { return _Stamp ?? (_Stamp = new Regex(@"^\[?([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9]|[0-9][0-9]:[0-9][0-9]:[0-9][0-9])([.,][0-9]+)?(Z|[+-][0-9][0-9]:?[0-9][0-9])?\]?[ \t]*", O)); } }

  static string Stamps(string t) {
    string[] L = Lines(t);
    int n = L.Length;
    string[] K = new string[n];
    for (int i = 0; i < n; i++) { Match m = Stamp.Match(L[i]); K[i] = m.Success ? L[i].Substring(m.Length) : ""; }
    List<string> o = new List<string>(n);
    for (int i = 0, j; i < n; i = j) {
      if (K[i] == "") { o.Add(L[i]); j = i + 1; continue; }
      for (j = i + 1; j < n && K[j] == K[i]; j++) { }
      int r = j - i;
      if (r >= 3) { o.Add(L[i]); o.Add("[skinflint: " + (r - 2) + " more lines like this, differing only in timestamp]"); o.Add(L[j - 1]); }
      else for (int x = i; x < j; x++) o.Add(L[x]);
    }
    return string.Join("\n", o.ToArray());
  }

  static Regex _FrameA; static Regex FrameA { get { return _FrameA ?? (_FrameA = new Regex(@"^[ \t]+at [^ \t]", O)); } }
  static Regex _FrameB; static Regex FrameB { get { return _FrameB ?? (_FrameB = new Regex(@"^[ \t]*#[0-9]+[ \t]", O)); } }
  static Regex _FramePy; static Regex FramePy { get { return _FramePy ?? (_FramePy = new Regex(@"^[ \t]+File ""[^""]*"", line [0-9]+", O)); } }
  static bool IsFrame(string l) { return FrameA.IsMatch(l) || FrameB.IsMatch(l); }

  static string Frames(string t) {
    string[] L = Lines(t);
    int n = L.Length;
    int[] UK = new int[n + 1];
    for (int i = 0; i < n; i++) {
      UK[i] = 0;
      if (IsFrame(L[i])) { UK[i] = 1; continue; }
      if (FramePy.IsMatch(L[i])) {
        UK[i] = 1;
        if (i < n - 1 && L[i + 1].StartsWith("    ", StringComparison.Ordinal) && !IsFrame(L[i + 1]) && !FramePy.IsMatch(L[i + 1])) { UK[i] = 2; UK[i + 1] = -1; i++; }
      }
    }
    List<string> o = new List<string>(n);
    for (int i = 0; i < n; ) {
      if (UK[i] <= 0) { o.Add(L[i]); i++; continue; }
      List<int> us = new List<int>(), ue = new List<int>();
      int j = i;
      for (; j < n && UK[j] > 0; j += UK[j]) { us.Add(j); ue.Add(j + UK[j] - 1); }
      int u = us.Count;
      if (u >= 8) {
        for (int a = 0; a < 3; a++) for (int x = us[a]; x <= ue[a]; x++) o.Add(L[x]);
        o.Add("[skinflint: " + (u - 5) + " stack frames omitted]");
        for (int a = u - 2; a < u; a++) for (int x = us[a]; x <= ue[a]; x++) o.Add(L[x]);
      } else for (int x = i; x < j; x++) o.Add(L[x]);
      i = j;
    }
    return string.Join("\n", o.ToArray());
  }

  static Regex _ErrWords; static Regex ErrWords { get { return _ErrWords ?? (_ErrWords = new Regex(@"(^|[^a-z0-9_])(error|errors|err|fail|failed|failure|failures|failing|fatal|exception|traceback|panic|denied|refused|timeout|timed out|assert|assertion|assertionerror|segfault|segmentation fault|abort|aborted|critical|warning|warnings|undefined reference|cannot|can't|not found|no such file|unable to|unexpected)([^a-z0-9_]|\z)", O)); } }
  static Regex _NoErr; static Regex NoErr { get { return _NoErr ?? (_NoErr = new Regex(@"(^|[^0-9])0 (errors?|failed|failures?|warnings?)|no (errors|failures|warnings)|(errors?|failures?|failed|warnings?)[ \t]*[:=][ \t]*0([^0-9]|\z)", O)); } }

  static Regex _ErrAny; static Regex ErrAny { get { return _ErrAny ?? (_ErrAny = new Regex(@"err|fail|fatal|exception|traceback|panic|denied|refused|timeout|timed out|assert|segfault|segmentation fault|abort|critical|warning|undefined reference|cannot|can't|not found|no such file|unable to|unexpected", O)); } }

  static bool IsError(string l) { string lo = Lower(l); return ErrWords.IsMatch(lo) && !NoErr.IsMatch(lo); }

  static Regex _PassA; static Regex PassA { get { return _PassA ?? (_PassA = new Regex(@"^(ok|PASS|PASSED)([ \t:]|\z)", O)); } }
  static Regex _PassB; static Regex PassB { get { return _PassB ?? (_PassB = new Regex(@"[ \t](ok|PASS|PASSED)\z", O)); } }
  static Regex _PassC; static Regex PassC { get { return _PassC ?? (_PassC = new Regex(@"^[ \t]*(PASS|PASSED)[ \t]", O)); } }

  static bool IsPass(string l) {
    if (!(PassA.IsMatch(l) || PassB.IsMatch(l) || PassC.IsMatch(l) || l.IndexOf(CHECK, StringComparison.Ordinal) >= 0)) return false;
    return !IsError(l);
  }

  static string Passes(string t) {
    string[] L = Lines(t);
    int n = L.Length;
    List<string> o = new List<string>(n);
    for (int i = 0, j; i < n; i = j) {
      if (!IsPass(L[i])) { o.Add(L[i]); j = i + 1; continue; }
      for (j = i + 1; j < n && IsPass(L[j]); j++) { }
      int r = j - i;
      if (r >= 10) { o.Add(L[i]); o.Add("[skinflint: " + (r - 2) + " more passing lines]"); o.Add(L[j - 1]); }
      else for (int x = i; x < j; x++) o.Add(L[x]);
    }
    return string.Join("\n", o.ToArray());
  }

  static string LongLines(string t) {
    string[] L = Lines(t);
    bool hit = false;
    for (int i = 0; i < L.Length; i++) if (L[i].Length > 4096) {
      string h = HeadBytes(L[i], 2048), z = TailBytes(L[i], 512);
      L[i] = h + " [skinflint: " + (L[i].Length - h.Length - z.Length) + " bytes cut from this line] " + z;
      hit = true;
    }
    return hit ? string.Join("\n", L) : t;
  }

  // ---------- cuts (4.2.7, 4.2.8, 4.3) ----------

  static string CutLines(string t, string orig, int slot, int n) {
    string saved = Spill(orig, slot);
    int a = Head + 1, b = n - Tail;
    string head = string.Join("\n", LN, 0, Head), tail = string.Join("\n", LN, b, n - b);
    if (!View) { head = Finer(head); tail = Finer(tail); }
    string rescue = RescueLines(a, b);
    return head + "\n[skinflint: cut lines " + a + "-" + b + " of " + n + Rescue + "." + saved + "]" + (rescue == "" ? "" : "\n" + rescue) + "\n" + tail;
  }

  // a and b are 1-based line numbers, as in the spec; LN is 0-based.
  static string RescueLines(int a, int b) {
    Rescue = "";
    // As on the awk side: one search of a 256-line block for any error word
    // rules out the whole block, so clean output never runs the full check.
    List<int> hits = new List<int>();
    for (int lo = a; lo <= b && hits.Count <= 12; lo += 256) {
      int hi = Math.Min(lo + 255, b);
      if (!ErrAny.IsMatch(Lower(string.Join("\n", LN, lo - 1, hi - lo + 1)))) continue;
      for (int i = lo; i <= hi && hits.Count <= 12; i++) if (IsError(LN[i - 1])) hits.Add(i);
    }
    int e = hits.Count;
    if (e == 0) return "";
    int c = Math.Min(e, 12);
    Rescue = "; kept " + c + " error " + (c == 1 ? "line" : "lines") + " below, with 1 line of context" + (e > 12 ? "; the full text has more" : "");
    List<int> sel = new List<int>();
    for (int i = 0; i < c; i++)
      for (int x = hits[i] - 1; x <= hits[i] + 1; x++)
        if (x >= a && x <= b && !sel.Contains(x)) sel.Add(x);
    sel.Sort();
    List<string> o = new List<string>();
    int last = 0;
    foreach (int i in sel) {
      if (last > 0 && i > last + 1) o.Add("[...]");
      o.Add(Cut300(LN[i - 1])); last = i;
    }
    return string.Join("\n", o.ToArray());
  }

  static string CutBytes(string t, string orig, int slot) {
    string saved = Spill(orig, slot);
    int x = Max / 2;
    string h = HeadBytes(t, x), z = TailBytes(t, x);
    return h + "\n[skinflint: cut " + (t.Length - h.Length - z.Length) + " bytes from the middle." + saved + "]\n" + z;
  }

  static Regex _Secret1; static Regex Secret1 { get { return _Secret1 ?? (_Secret1 = new Regex(@"-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22}|xox[abprs]-[A-Za-z0-9-]{10}|sk-[A-Za-z0-9_-]{20}", O)); } }
  static Regex _Secret2; static Regex Secret2 { get { return _Secret2 ?? (_Secret2 = new Regex(@"(password|passwd|secret|token|api[_-]?key)[""']?[ \t]*[:=][ \t]*[""']?[^ \t""']{8}|authorization:[ \t]*bearer[ \t]+[^ \t]{16}", O)); } }

  static string Spill(string orig, int slot) {
    if (Env("SKINFLINT_SPILL") == "0" || Tuid == "") return "";
    if (Secret1.IsMatch(orig) || Secret2.IsMatch(Lower(orig))) return " Full text not saved: it looks like it holds a credential";
    if (!CanSpill) return "";
    string p = SpillDir + "/" + SafeTool + "-" + Tuid + "-" + slot + ".txt";
    if (!WriteFile(p, orig)) return "";
    Spilled = true;
    return " Full text: " + p + " (search it rather than re-running)";
  }

  static void PruneSpill() {
    try {
      FileInfo[] fs = new DirectoryInfo(SpillDir).GetFiles("*.txt");
      if (fs.Length <= 60) return;
      Array.Sort(fs, (x, y) => y.LastWriteTimeUtc.CompareTo(x.LastWriteTimeUtc));
      for (int i = 40; i < fs.Length; i++) try { fs[i].Delete(); } catch { }
    } catch { }
  }

  // ---------- stats (2) ----------

  static Regex _StatsRe; static Regex StatsRe { get { return _StatsRe ?? (_StatsRe = new Regex(@"^saved ([0-9]+)\nevents ([0-9]+)\n(reply ([0-9]+)\nreplies ([0-9]+)\ninjected ([0-9]+)\n)?\z", O)); } }

  // Adds to the five counters. A file written before the reply and injected
  // counters existed holds only the first two lines.
  static void AddStats(long ds, long de, long dr, long dn, long di) {
    if (!CanWrite) return;
    string p = State + "/stats";
    long[] v = new long[5];
    if (File.Exists(p)) {
      Match m = StatsRe.Match(ReadFile(p) ?? "");
      if (!m.Success) return;
      int[] g = { 1, 2, 4, 5, 6 };
      for (int i = 0; i < 5; i++)
        if (m.Groups[g[i]].Success && !long.TryParse(m.Groups[g[i]].Value, out v[i])) return;
    }
    WriteFile(p, "saved " + (v[0] + ds) + "\nevents " + (v[1] + de) + "\nreply " + (v[2] + dr) + "\nreplies " + (v[3] + dn) + "\ninjected " + (v[4] + di) + "\n");
  }
}
}
