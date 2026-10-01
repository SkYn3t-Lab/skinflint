# skinflint hooks in POSIX awk (mawk, gawk, BWK awk, busybox awk).
# hooks/run.sh runs this with LC_ALL=C, so every string operation is on bytes.
# Section numbers refer to SPEC.md, which this file implements.

BEGIN {
  init()
  RS = "\377"
  PAYLOAD = read_stdin()
  if (!valid_utf8(PAYLOAD)) exit 0
  ROOT = json_parse(PAYLOAD)
  PAYLOAD_T = JS
  if (!ROOT || JT[ROOT] != "o") exit 0
  load_config()
  load_session()
  HOOK = ENVIRON["SF_HOOK"]
  if (HOOK == "activate") exit hook_activate()
  if (HOOK == "prompt") exit hook_prompt()
  if (HOOK == "subagent") exit hook_subagent()
  if (HOOK == "compress") exit hook_compress()
  exit 0
}

function init(   i) {
  for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
  HEX = "0123456789abcdef"
  CH = ENVIRON["SF_BB"] == "1" ? 16384 : 2147483647
  UP = "SKINFLINT"
  STATE = ENVIRON["SF_STATE"]
  SESS = STATE "/sessions"; SPILL = STATE "/spill"
  CLAUDE_DIR = ENVIRON["SF_CLAUDE_DIR"]
  PLUGIN = ENVIRON["SF_ROOT"]
  CAN_WRITE = ENVIRON["SF_W"] == "1"
  CAN_SPILL = ENVIRON["SF_WS"] == "1"
  CHECK = "\342\234\223"
  WSP = "[ \t\n\r\013\014]"
  # Intervals are spelled out: older mawk has no {n}.
  AN36 = rep("[A-Za-z0-9]", 36)
  SECRET1 = "-----BEGIN [A-Z ]*PRIVATE KEY-----|AKIA" rep("[0-9A-Z]", 16) "|gh[pousr]_" AN36 \
    "|github_pat_" rep("[A-Za-z0-9_]", 22) "|xox[abprs]-" rep("[A-Za-z0-9-]", 10) "|sk-" rep("[A-Za-z0-9_-]", 20)
  SECRET2 = "(password|passwd|secret|token|api[_-]?key)[\"']?[ \t]*[:=][ \t]*[\"']?" rep("[^ \t\"']", 8) \
    "|authorization:[ \t]*bearer[ \t]+" rep("[^ \t]", 16)
}

function rep(s, n,   out) { out = ""; while (n-- > 0) out = out s; return out }

# ---------- input and files ----------

function read_stdin(   r, out, n) {
  out = ""; n = 0
  while ((getline r < "/dev/stdin") > 0) out = out (n++ ? "\377" : "") r
  return out
}

# Whole file, "" when absent. FILE_OK is 1 when something was read.
function readfile(p,   r, out, n) {
  out = ""; n = 0; FILE_OK = 0
  if (p == "") return ""
  while ((getline r < p) > 0) { out = out (n++ ? "\377" : "") r; FILE_OK = 1 }
  close(p)
  return out
}

function writefile(p, data) {
  printf "%s", data > p
  close(p)
}

# Invalid when any of these occurs: a byte that never appears in UTF-8, a
# lead byte without enough continuation bytes, a continuation byte with no
# lead, too many continuation bytes, or an overlong / surrogate / too-large
# form. One search, where matching the whole input costs ten times as much.
function valid_utf8(s) {
  if (s !~ /[\200-\377]/) return 1
  return s !~ /[\300\301\365-\377]|[\302-\364]([^\200-\277]|$)|[\340-\364][\200-\277]([^\200-\277]|$)|[\360-\364][\200-\277][\200-\277]([^\200-\277]|$)|(^|[\001-\177])[\200-\277]|[\302-\337][\200-\277][\200-\277]|[\340-\357][\200-\277][\200-\277][\200-\277]|[\360-\364][\200-\277][\200-\277][\200-\277][\200-\277]|\340[\200-\237]|\355[\240-\277]|\360[\200-\217]|\364[\220-\277]/
}

function no_bom(s) { if (substr(s, 1, 3) == "\357\273\277") return substr(s, 4); return s }

# ---------- JSON (1) ----------
# Nodes: JT type (o a s n t f z), JV decoded string, JN child count,
# JK[id,i] key, JC[id,i] child, JB/JE byte span in the parsed text,
# JDUP[id] set when an object repeats a key. U+0000 decodes to C0 80, which
# valid UTF-8 never contains, so a NUL is always detectable.

# Escaped backslashes become byte FF and escaped quotes byte FE before
# parsing (valid UTF-8 has neither), so the end of a string is simply the next
# quote. raw() turns them back when a value is copied out as JSON text.
function json_parse(s,   id) {
  if (index(s, "\\\\")) s = subst("bs2", s, "bs")
  if (index(s, "\\\"")) s = subst("bsq", s, "bs")
  JS = s; JP = 1; JL = length(s); JERR = 0
  json_ws()
  id = json_value()
  if (JERR) return 0
  json_ws()
  if (JP <= JL) return 0
  return id
}

function json_ws(   c) {
  while (JP <= JL) {
    c = substr(JS, JP, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") JP++
    else break
  }
}

function json_new(t, v) {
  JCOUNT++
  JT[JCOUNT] = t; JV[JCOUNT] = v; JN[JCOUNT] = 0; JB[JCOUNT] = JP
  return JCOUNT
}

function json_value(   c, id, rest, k, cid, i) {
  if (JP > JL) { JERR = 1; return 0 }
  c = substr(JS, JP, 1)
  if (c == "{") {
    id = json_new("o", ""); JP++; json_ws()
    if (substr(JS, JP, 1) == "}") { JP++; JE[id] = JP - 1; return id }
    while (1) {
      json_ws()
      if (substr(JS, JP, 1) != "\"") { JERR = 1; return 0 }
      k = json_string(); if (JERR) return 0
      json_ws()
      if (substr(JS, JP, 1) != ":") { JERR = 1; return 0 }
      JP++; json_ws()
      cid = json_value(); if (JERR) return 0
      for (i = 1; i <= JN[id]; i++) if (JK[id, i] == k) JDUP[id] = 1
      JN[id]++; JK[id, JN[id]] = k; JC[id, JN[id]] = cid
      json_ws()
      c = substr(JS, JP, 1)
      if (c == ",") { JP++; continue }
      if (c == "}") { JP++; JE[id] = JP - 1; return id }
      JERR = 1; return 0
    }
  }
  if (c == "[") {
    id = json_new("a", ""); JP++; json_ws()
    if (substr(JS, JP, 1) == "]") { JP++; JE[id] = JP - 1; return id }
    while (1) {
      json_ws()
      cid = json_value(); if (JERR) return 0
      JN[id]++; JC[id, JN[id]] = cid
      json_ws()
      c = substr(JS, JP, 1)
      if (c == ",") { JP++; continue }
      if (c == "]") { JP++; JE[id] = JP - 1; return id }
      JERR = 1; return 0
    }
  }
  if (c == "\"") { id = json_new("s", ""); JV[id] = json_string(); JE[id] = JP - 1; return JERR ? 0 : id }
  rest = substr(JS, JP, 5)
  if (substr(rest, 1, 4) == "true") { id = json_new("t", ""); JP += 4; JE[id] = JP - 1; return id }
  if (rest == "false") { id = json_new("f", ""); JP += 5; JE[id] = JP - 1; return id }
  if (substr(rest, 1, 4) == "null") { id = json_new("z", ""); JP += 4; JE[id] = JP - 1; return id }
  rest = substr(JS, JP, 400)
  if (match(rest, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][-+]?[0-9]+)?/)) {
    id = json_new("n", substr(rest, 1, RLENGTH)); JP += RLENGTH; JE[id] = JP - 1
    return id
  }
  JERR = 1; return 0
}

# At an opening quote: the decoded string; JP moves past the closing quote.
function json_string(   rest, e, raw) {
  rest = substr(JS, JP + 1)
  e = index(rest, "\"")
  if (!e) { JERR = 1; return "" }
  raw = substr(rest, 1, e - 1)
  JP += e + 1
  if (raw ~ /[\001-\037]/) { JERR = 1; return "" }
  if (index(raw, "\\") == 0) {
    if (index(raw, "\377")) raw = swap(raw, "\377", "\\")
    if (index(raw, "\376")) raw = subst("quote", raw, "any")
    return raw
  }
  if (raw ~ /\\([^"\/bfnrtu]|$)|\\u([^0-9A-Fa-f]|.[^0-9A-Fa-f]|..[^0-9A-Fa-f]|...[^0-9A-Fa-f]|.?.?.?$)/) { JERR = 1; return "" }
  return json_unescape(raw)
}

# Escaped backslashes and quotes are already bytes FF and FE (json_parse),
# so every remaining backslash starts an escape.
function json_unescape(raw,   n, parts, i, cp, nx, out, k) {
  if (CH < 2147483647) return unescape_split(raw)
  if (index(raw, "\\n")) gsub(/\\n/, "\n", raw)
  if (index(raw, "\\t")) gsub(/\\t/, "\t", raw)
  if (index(raw, "\\r")) gsub(/\\r/, "\r", raw)
  if (index(raw, "\\b")) gsub(/\\b/, "\010", raw)
  if (index(raw, "\\f")) gsub(/\\f/, "\014", raw)
  if (index(raw, "\\/")) gsub(/\\\//, "/", raw)
  if (index(raw, "\\u")) {
    n = split(raw, parts, /\\u/)
    k = 0
    out[++k] = parts[1]
    for (i = 2; i <= n; i++) {
      cp = hex4(substr(parts[i], 1, 4))
      if (cp >= 55296 && cp <= 56319 && length(parts[i]) == 4 && i < n) {
        nx = hex4(substr(parts[i + 1], 1, 4))
        if (nx >= 56320 && nx <= 57343) {
          out[++k] = utf8(65536 + (cp - 55296) * 1024 + (nx - 56320)) substr(parts[i + 1], 5)
          i++
          continue
        }
      }
      out[++k] = utf8(cp) substr(parts[i], 5)
    }
    raw = join(out, 1, k, "")
  }
  if (index(raw, "\377")) raw = swap(raw, "\377", "\\")
  if (index(raw, "\376")) raw = subst("quote", raw, "any")
  return raw
}

# The same decoding for busybox, where gsub with many matches is slow and a
# one-character split is not: split at every backslash, then each piece after
# the first starts with its escape letter. A JSON string holds no raw newline,
# so BWK-style newline splitting cannot interfere.
function unescape_split(raw,   n, P, i, c, cp, nx) {
  n = split(raw, P, "\\")
  for (i = 2; i <= n; i++) {
    c = substr(P[i], 1, 1)
    if (c == "n") P[i] = "\n" substr(P[i], 2)
    else if (c == "t") P[i] = "\t" substr(P[i], 2)
    else if (c == "r") P[i] = "\r" substr(P[i], 2)
    else if (c == "b") P[i] = "\010" substr(P[i], 2)
    else if (c == "f") P[i] = "\014" substr(P[i], 2)
    # "/": the piece already starts with the slash, keep it as it is
    else if (c == "u") {
      cp = hex4(substr(P[i], 2, 4))
      if (cp >= 55296 && cp <= 56319 && length(P[i]) == 5 && i < n && substr(P[i + 1], 1, 1) == "u") {
        nx = hex4(substr(P[i + 1], 2, 4))
        if (nx >= 56320 && nx <= 57343) {
          P[i] = utf8(65536 + (cp - 55296) * 1024 + (nx - 56320)); P[i + 1] = substr(P[i + 1], 6)
          i++
          continue
        }
      }
      P[i] = utf8(cp) substr(P[i], 6)
    }
  }
  raw = join(P, 1, n, "")
  if (index(raw, "\377")) raw = swap(raw, "\377", "\\")
  if (index(raw, "\376")) raw = subst("quote", raw, "any")
  return raw
}

# A parsed value as its original JSON text.
function rawtext(id,   t) {
  t = substr(PAYLOAD_T, JB[id], JE[id] - JB[id] + 1)
  if (index(t, "\377")) t = swap(t, "\377", "\\\\")
  if (index(t, "\376")) t = swap(t, "\376", "\\\"")
  return t
}

function hex4(h,   i, v) {
  v = 0
  for (i = 1; i <= 4; i++) v = v * 16 + index(HEX, tolower(substr(h, i, 1))) - 1
  return v
}

function utf8(cp) {
  if (cp == 0) return "\300\200"
  if (cp >= 55296 && cp <= 57343) return "\357\277\275"
  if (cp < 128) return sprintf("%c", cp)
  if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
  if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
  return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}

# Last occurrence wins (1).
function json_get(id, key,   i) {
  if (JT[id] != "o") return 0
  for (i = JN[id]; i >= 1; i--) if (JK[id, i] == key) return JC[id, i]
  return 0
}

function jstr(id, key,   v) { v = json_get(id, key); return (v && JT[v] == "s") ? JV[v] : "" }
function jbool(id, key,   v) { v = json_get(id, key); return v && JT[v] == "t" }

# Balanced join: a running `out = out x` is quadratic in mawk.
function join(a, lo, hi, sep,   b, n, i, k) {
  if (lo > hi) return ""
  n = 0
  for (i = lo; i <= hi; i++) b[++n] = a[i]
  while (n > 1) {
    k = 0
    for (i = 1; i + 1 <= n; i += 2) b[++k] = b[i] sep b[i + 1]
    if (i == n) b[++k] = b[n]
    n = k
  }
  return b[1]
}

# ---------- big strings ----------
# busybox awk's gsub with a regex slows down steeply on long strings with
# many matches (3 MB, 40k matches: 0.9 s), so under busybox (SF_BB, set by
# run.sh) gsub works on 16 KB pieces. Other awks are fastest in one pass and
# get CH so large that nothing is ever cut. (split on one character is fast
# everywhere and needs none of this.) Pieces are cut only where no match can
# straddle the cut:
#   line  after a run of newlines (every clean rule stays within a line)
#   bs    not inside a run of backslashes (the raw JSON escapes \\ and \")
#   any   anywhere (single-byte patterns)
function chunk(s, mode, C,   L, k, p, q, x) {
  L = length(s); k = 0
  for (p = 1; p <= L; p = q) {
    q = p + CH
    if (q > L) { C[++k] = substr(s, p); break }
    if (mode == "line") {
      for (x = 0; q <= L; q += CH) if ((x = index(substr(s, q, CH), "\n"))) break
      if (!x) { C[++k] = substr(s, p); break }
      q += x
      while (q <= L && substr(s, q, 1) == "\n") q++
    } else if (mode == "bs") while (q <= L && substr(s, q - 1, 1) == "\\") q++
    C[++k] = substr(s, p, q - p)
  }
  return k
}

# One of the fixed substitutions below over s, piecewise under busybox.
# Each is a regex literal: busybox recompiles a regex held in a string on
# every call, which would cost a compile per piece.
function subst(which, s, mode,   C, k, i) {
  if (length(s) <= CH) return subst1(which, s)
  k = chunk(s, mode, C)
  for (i = 1; i <= k; i++) C[i] = subst1(which, C[i])
  return join(C, 1, k, "")
}

function subst1(which, s) {
  if (which == "bs2") gsub(/\\\\/, "\377", s)
  else if (which == "bsq") gsub(/\\"/, "\376", s)
  else if (which == "quote") gsub(/\376/, "\"", s)
  else if (which == "csi") gsub(/\033\[[0-9;?]*[ -\/]*[@-~]/, "", s)
  else if (which == "osc") gsub(/\033\][^\007\033\n]*(\007|\033\\)/, "", s)
  else if (which == "ws") gsub(/[ \t]+\n/, "\n", s)
  else if (which == "wscr") gsub(/[ \t]+\r\n/, "\r\n", s)
  else if (which == "blank") gsub(/\n\n\n+/, "\n\n", s)
  return s
}

# Replace every literal `from` with the literal `to`. gsub replacement
# strings treat backslash differently across awks, so this splits instead.
# A one-byte separator goes in brackets: BWK split on one char also splits
# on newlines.
function swap(s, from, to,   parts, n, re) {
  re = from
  if (length(re) == 1) re = "[" re "]"
  n = split(s, parts, re)
  return n ? join(parts, 1, n, to) : s
}

function json_str(s,   i, c) {
  if (index(s, "\\")) s = swap(s, "\\\\", "\\\\")
  if (index(s, "\"")) s = swap(s, "\"", "\\\"")
  if (s ~ /[\001-\037]/) {
    for (i = 1; i < 32; i++) {
      c = sprintf("%c", i)
      if (!index(s, c)) continue
      if (i == 10) s = swap(s, c, "\\n")
      else if (i == 13) s = swap(s, c, "\\r")
      else if (i == 9) s = swap(s, c, "\\t")
      else if (i == 8) s = swap(s, c, "\\b")
      else if (i == 12) s = swap(s, c, "\\f")
      else s = swap(s, c, sprintf("\\u%04x", i))
    }
  }
  if (index(s, "\300\200")) s = swap(s, "\300\200", "\\u0000")
  return "\"" s "\""
}

# ---------- text helpers (1) ----------

function trim(s) {
  sub(/^[ \t\n\r\013\014]+/, "", s)
  sub(/[ \t\n\r\013\014]+$/, "", s)
  return s
}

function lines_of(t, arr,   n) {
  n = split(t, arr, "\n")
  if (n == 0) { arr[1] = ""; n = 1 }
  return n
}

function is_cont(c) { return c >= "\200" && c <= "\277" }

# First n bytes, moved back to a UTF-8 boundary.
function head_bytes(s, n) {
  if (n >= length(s)) return s
  while (n > 0 && is_cont(substr(s, n + 1, 1))) n--
  return substr(s, 1, n)
}

# Last n bytes, moved forward to a UTF-8 boundary.
function tail_bytes(s, n,   st) {
  if (n >= length(s)) return s
  st = length(s) - n + 1
  while (st <= length(s) && is_cont(substr(s, st, 1))) st++
  return substr(s, st)
}

function cut300(l) { return length(l) > 300 ? head_bytes(l, 300) "..." : l }

function num(k, fb,   v) {
  v = ENVIRON["SKINFLINT_" k]
  if (v !~ /^[0-9]+$/ || length(v) > 9 || v + 0 <= 0) return fb
  return v + 0
}

function ctx(event, text) {
  return "{\"hookSpecificOutput\":{\"hookEventName\":\"" event "\",\"additionalContext\":" json_str(text) "}}"
}

# ---------- config, mode, sections (2, 3) ----------

# The user config, then the project's .claude/skinflint.json: a valid key
# in the project file replaces the user's value for that key.
function load_config() {
  CFG_MODE = ""; CFG_PROSE = ""; CFG_CODE = ""
  config_file(ENVIRON["SF_CFG"])
  config_file(ENVIRON["SF_PC"])
}

function config_file(path,   raw, id, v, s, m) {
  if (path == "") return
  raw = no_bom(readfile(path))
  if (!FILE_OK || !valid_utf8(raw)) return
  id = json_parse(raw)
  if (!id || JT[id] != "o") return
  m = tolower(jstr(id, "defaultMode"))
  if (m == "on" || m == "off") CFG_MODE = m
  s = json_get(id, "sections")
  if (s && JT[s] == "o") {
    v = json_get(s, "prose"); if (v && (JT[v] == "t" || JT[v] == "f")) CFG_PROSE = (JT[v] == "t")
    v = json_get(s, "code"); if (v && (JT[v] == "t" || JT[v] == "f")) CFG_CODE = (JT[v] == "t")
  }
}

function default_mode(   e) {
  e = tolower(ENVIRON["SKINFLINT_DEFAULT_MODE"])
  if (e == "on" || e == "off") return e
  if (CFG_MODE != "") return CFG_MODE
  return "on"
}

function load_session(   m) {
  SID = jstr(ROOT, "session_id")
  if (SID !~ /^[A-Za-z0-9_-]+$/ || length(SID) > 128) SID = ""
  MODE = default_mode()
  if (SID == "") return
  m = tolower(trim(readfile(SESS "/" SID ".mode")))
  if (m == "on" || m == "off") MODE = m
}

function sections(   i, p, raw, id, v, st) {
  PROSE = 1; CODE = 1
  if (CFG_PROSE != "") PROSE = CFG_PROSE
  if (CFG_CODE != "") CODE = CFG_CODE
  if (CFG_PROSE != "") return
  for (i = 1; i <= 3; i++) {
    p = ENVIRON["SF_S" i]
    if (p == "") continue
    raw = no_bom(readfile(p))
    if (!index(raw, "\"outputStyle\"") || !valid_utf8(raw)) continue
    id = json_parse(raw)
    if (!id || JT[id] != "o") continue
    v = json_get(id, "outputStyle")
    if (!v || JT[v] != "s") continue
    st = trim(JV[v])
    if (st == "") continue
    if (tolower(st) != "default") PROSE = 0
    return
  }
}

function reminder(   s) {
  sections()
  s = UP " ON."
  if (PROSE) s = s " Prose: answer first, then only what the user needs to act; for a problem, the likely cause and its fix, not every possibility; for a comparison, the pick first, then at most three one-sentence reasons; sentences, no headings or bullet lists (number steps only when they run in order)."
  if (CODE) s = s " Code: smallest change that works, reuse before writing, nothing speculative; the code first, then at most three short lines on what you left out and when to add it; no alternatives, demos or tests unless asked; when asked to write or show code, reply with it and create no file unless the user named one."
  return s " Code, commit messages and security warnings stay in full sentences."
}

# ---------- SessionStart (5.1) ----------

function hook_activate(   src, body) {
  src = jstr(ROOT, "source")
  if (MODE == "off") return src == "startup" ? 4 : 0
  if (src == "resume" || src == "fork") {
    printf "%s", ctx("SessionStart", UP " ON (resumed). The rules are already in this conversation; the skinflint skill has them if not.")
    return 0
  }
  sections()
  body = ruleset(readfile(PLUGIN "/skills/skinflint/SKILL.md"))
  printf "%s", ctx("SessionStart", UP " ON\n\n" body)
  return src == "startup" ? 4 : 0
}

function ruleset(s,   lines, n, i, k, out, skip, start) {
  s = no_bom(s)
  if (index(s, "\r")) s = swap(s, "\r\n", "\n")
  n = lines_of(s, lines)
  start = 1
  if (lines[1] == "---")
    for (i = 2; i <= n; i++) if (lines[i] == "---") { start = i + 1; break }
  k = 0; skip = 0
  for (i = start; i <= n; i++) {
    if (substr(lines[i], 1, 3) == "## ")
      skip = (!PROSE && substr(lines[i], 1, 8) == "## Prose") || (!CODE && substr(lines[i], 1, 7) == "## Code")
    if (!skip) out[++k] = lines[i]
  }
  s = join(out, 1, k, "\n")
  sub(/^[ \t\n\r\013\014]+/, "", s)
  return s
}

# ---------- UserPromptSubmit (5.2) ----------

function hook_prompt(   c, want) {
  c = command_form(jstr(ROOT, "prompt"))
  want = ""
  if (c == "stop skinflint" || c == "skinflint off" || c == "skinflint mode off" || c == "/skinflint off" || \
      c == "disable skinflint" || c == "turn off skinflint" || c == "deactivate skinflint" || c == "normal mode") want = "off"
  else if (c == "/skinflint" || c == "/skinflint on" || c == "skinflint on" || c == "skinflint mode" || \
      c == "skinflint mode on" || c == "start skinflint" || c == "enable skinflint" || c == "turn on skinflint" || \
      c == "activate skinflint" || c == "use skinflint") want = "on"
  if (want != "") {
    if (SID != "" && CAN_WRITE) writefile(SESS "/" SID ".mode", want)
    MODE = want
  }
  if (MODE == "on") printf "%s", ctx("UserPromptSubmit", reminder())
  else if (want == "off") printf "%s", ctx("UserPromptSubmit", UP " OFF. Write normally until the user turns it back on.")
  return 0
}

function command_form(p,   a, z) {
  p = trim(tolower(p))
  a = substr(p, 1, 1); z = substr(p, length(p), 1)
  if (length(p) >= 2 && a == z && (a == "`" || a == "\"" || a == "'")) p = trim(substr(p, 2, length(p) - 2))
  z = substr(p, length(p), 1)
  if (z == "." || z == "!") p = trim(substr(p, 1, length(p) - 1))
  gsub(/[ \t\n\r\013\014]+/, " ", p)
  if (index(p, "skin flint")) p = swap(p, "skin flint", "skinflint")
  if (index(p, "skin-flint")) p = swap(p, "skin-flint", "skinflint")
  return p
}

# ---------- SubagentStart (5.3) ----------

function hook_subagent() {
  if (MODE == "on") printf "%s", ctx("SubagentStart", reminder() " You are a subagent: write your final report the same way.")
  return 0
}

# ---------- PostToolUse (4) ----------

function hook_compress(   tool, resp, ti, i, v, k, unit, total, saved, dup, rc, nuls) {
  if (MODE != "on" || ENVIRON["SKINFLINT_COMPRESS"] == "0") return 0
  tool = jstr(ROOT, "tool_name")
  if (!tool_ok(tool)) return 0
  resp = json_get(ROOT, "tool_response")
  if (!resp || JT[resp] == "z") return 0
  if (JT[resp] == "o" && (jbool(resp, "isImage") || jbool(resp, "interrupted") || json_get(resp, "persistedOutputPath"))) return 0
  ti = json_get(ROOT, "tool_input")
  if (ti && JT[ti] == "o")
    for (i = 1; i <= JN[ti]; i++) {
      v = JC[ti, i]
      if (JT[v] == "s" && (index(JV[v], "skinflint/spill") || index(JV[v], "skinflint\\spill"))) return 0
    }
  NS = 0
  if (!find_slots(resp)) return 0
  if (NS == 0) return 0

  TOOL = tool; SAFE_TOOL = safe(tool); if (SAFE_TOOL == "") SAFE_TOOL = "tool"
  TUID = safe(jstr(ROOT, "tool_use_id"))
  MAX = num("MAX_BYTES", 8000); HEAD = num("HEAD_LINES", 60); TAIL = num("TAIL_LINES", 40)
  VIEW = ((tool == "Bash" || tool == "PowerShell") && ti && JT[ti] == "o" && is_view(jstr(ti, "command")))

  # U+0000 (C0 80 here) is removed first: Windows tools that write UTF-16
  # arrive with a NUL after every ASCII character. Each counts as one byte.
  total = 0; nuls = 0
  for (k = 1; k <= NS; k++) {
    OLD[k] = JV[SLOT[k]]
    if (index(OLD[k], "\300\200")) { v = swap(OLD[k], "\300\200", ""); nuls += (length(OLD[k]) - length(v)) / 2; OLD[k] = v }
    NEW[k] = OLD[k]; total += length(OLD[k])
  }
  unit = join(OLD, 1, NS, "\036")
  dup = dedup(unit)
  SPILLED = 0
  if (!dup) for (k = 1; k <= NS; k++) NEW[k] = pipeline(OLD[k], k)
  saved = nuls
  for (k = 1; k <= NS; k++) saved += length(OLD[k]) - length(NEW[k])
  if (saved < 64) return SPILLED ? 3 : 0
  for (k = 1; k <= NS; k++) NEWOF[SLOT[k]] = NEW[k]
  printf "%s", "{\"hookSpecificOutput\":{\"hookEventName\":\"PostToolUse\",\"updatedToolOutput\":" emit(resp) "}}"
  add_stats(saved)
  return SPILLED ? 3 : 0
}

function tool_ok(t,   list, n, parts, i) {
  if (t == "" || t == "Read" || t == "Edit" || t == "Write" || t == "MultiEdit" || t == "NotebookEdit" || t == "NotebookRead") return 0
  list = ENVIRON["SKINFLINT_TOOLS"]
  if (list != "") {
    n = split(list, parts, ",")
    for (i = 1; i <= n; i++) if (trim(parts[i]) == t) return 1
    return 0
  }
  if (t == "Bash" || t == "PowerShell" || t == "Agent" || t == "WebFetch" || t == "WebSearch" || t == "Grep" || t == "Glob") return 1
  return substr(t, 1, 5) == "mcp__"
}

function safe(s) { gsub(/[^A-Za-z0-9_-]/, "", s); return s }

# 4.1.1. Returns 0 when a container holding slots repeats a key.
function find_slots(id,   i, c) {
  if (JT[id] == "s") { SLOT[++NS] = id; return 1 }
  if (JT[id] == "a") return find_blocks(id)
  if (JT[id] != "o") return 1
  for (i = 1; i <= JN[id]; i++) {
    c = JC[id, i]
    if (JT[c] == "s" && (JK[id, i] == "stdout" || JK[id, i] == "stderr" || JK[id, i] == "output" || \
        JK[id, i] == "content" || JK[id, i] == "text" || JK[id, i] == "result")) { SLOT[++NS] = c; HOLDS[id] = 1 }
    else if (JT[c] == "a" && JK[id, i] == "content") { if (!find_blocks(c)) return 0; if (HOLDS[c]) HOLDS[id] = 1 }
  }
  return !(HOLDS[id] && JDUP[id])
}

function find_blocks(arr,   i, b, j, t) {
  for (i = 1; i <= JN[arr]; i++) {
    b = JC[arr, i]
    if (JT[b] != "o") continue
    t = json_get(b, "type")
    if (!t || JT[t] != "s" || JV[t] != "text") continue
    for (j = 1; j <= JN[b]; j++)
      if (JK[b, j] == "text" && JT[JC[b, j]] == "s") { SLOT[++NS] = JC[b, j]; HOLDS[b] = 1 }
    if (HOLDS[b] && JDUP[b]) return 0
    if (HOLDS[b]) HOLDS[arr] = 1
  }
  return 1
}

# Rebuild (4.6): rewritten slots re-encoded, containers of slots rebuilt,
# everything else copied as its original JSON text.
function emit(id,   i, parts) {
  if (id in NEWOF) return json_str(NEWOF[id])
  if (!HOLDS[id]) return rawtext(id)
  if (JT[id] == "a") {
    for (i = 1; i <= JN[id]; i++) parts[i] = emit(JC[id, i])
    return "[" join(parts, 1, JN[id], ",") "]"
  }
  for (i = 1; i <= JN[id]; i++) parts[i] = json_str(JK[id, i]) ":" emit(JC[id, i])
  return "{" join(parts, 1, JN[id], ",") "}"
}

function is_view(cmd,   w, rest) {
  if (index(cmd, "|")) return 0
  rest = cmd
  while (1) {
    sub(/^[ \t\n\r\013\014]+/, "", rest)
    if (!match(rest, /^[^ \t\n\r\013\014]+/)) return 0
    w = substr(rest, 1, RLENGTH)
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { rest = substr(rest, RLENGTH + 1); continue }
    break
  }
  if (w == "sudo") {
    rest = substr(rest, RLENGTH + 1)
    sub(/^[ \t\n\r\013\014]+/, "", rest)
    if (!match(rest, /^[^ \t\n\r\013\014]+/)) return 0
    w = substr(rest, 1, RLENGTH)
  }
  if (tolower(w) ~ /^(cat|head|tail|sed|nl|less|more|bat|batcat|diff|jq|xxd|od|get-content|gc|type)$/) return 1
  if (w != "git") return 0
  rest = substr(rest, RLENGTH + 1)
  sub(/^[ \t\n\r\013\014]+/, "", rest)
  return match(rest, /^(show|diff|cat-file)([ \t\n\r\013\014]|$)/) > 0
}

# ---------- dedup (4.5) ----------

function dedup(unit,   p, raw, nl, prevId, n, lines, i, k, out) {
  if (ENVIRON["SKINFLINT_DEDUP"] == "0" || SID == "" || TUID == "") return 0
  if (length(unit) < 2048 || length(unit) > 1048576) return 0
  p = SESS "/" SID "." SAFE_TOOL ".last"
  raw = readfile(p)
  nl = index(raw, "\n")
  prevId = nl ? substr(raw, 1, nl - 1) : ""
  IS_DUP = (nl && prevId != TUID && substr(raw, nl + 1) == unit)
  if (CAN_WRITE) writefile(p, TUID "\n" unit)
  if (!IS_DUP) return 0
  n = lines_of(unit, lines)
  k = (n < 5 ? n : 5)
  for (i = 1; i <= k; i++) out[i] = cut300(lines[i])
  NEW[1] = "[skinflint: same output as the previous " TOOL " call (" length(unit) " bytes, " n " lines). It starts:]\n" join(out, 1, k, "\n")
  for (i = 2; i <= NS; i++) NEW[i] = ""
  return 1
}

# ---------- per-slot pipeline (4.2) ----------
# Whole-text steps are single regex or string passes. Per-line work runs only
# on text that stays: small text, or the head and tail blocks of a cut.

function pipeline(t, slot,   n) {
  if (length(t) <= 1024) return t
  if (VIEW) {
    if (length(t) <= MAX + int(MAX / 2)) return t
    n = lines_of(t, LN)
    return n > HEAD + TAIL ? cut_lines(t, t, slot, n) : cut_bytes(t, t, slot)
  }
  ORIG = t
  t = clean(t)
  n = repeats(lines_of(t, LN))
  if (RCHANGED) t = join(LN, 1, n, "\n")
  if (length(t) > MAX && n > HEAD + TAIL) return cut_lines(t, ORIG, slot, n)
  t = finer(t)
  if (length(t) > MAX) t = cut_bytes(t, ORIG, slot)
  return t
}

# 4.2.3 to 4.2.6, each skipped when one search shows it cannot apply.
function finer(t) {
  if (t ~ /[0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) t = stamps(t)
  if (t ~ /(^|\n)([ \t]+at [^ \t]|[ \t]*#[0-9]+[ \t]|[ \t]+File ")/) t = frames(t)
  if (t ~ /(^|\n)(ok|PASS|PASSED)([ \t:]|\n|$)|[ \t](ok|PASS|PASSED)(\n|$)|(^|\n)[ \t]*(PASS|PASSED)[ \t]/ || index(t, CHECK)) t = passes(t)
  if (length(t) > 4096) t = longlines(t)
  return t
}

function clean(t,   n, L, i, body, cr, parts, m) {
  if (index(t, "\033")) { t = subst("csi", t, "line"); t = subst("osc", t, "line") }
  if (t ~ /\r[^\n]/) {
    n = lines_of(t, L)
    for (i = 1; i <= n; i++) {
      body = L[i]; cr = ""
      if (substr(body, length(body), 1) == "\r") { cr = "\r"; body = substr(body, 1, length(body) - 1) }
      if (index(body, "\r")) { m = split(body, parts, "\r"); body = parts[m] }
      L[i] = body cr
    }
    t = join(L, 1, n, "\n")
  }
  if (t ~ /[ \t](\r?\n|\r?$)/) {
    t = subst("ws", t, "line")
    if (index(t, "\r")) t = subst("wscr", t, "line")
    sub(/[ \t]+$/, "", t)
    sub(/[ \t]+\r$/, "\r", t)
  }
  if (index(t, "\n\n\n")) t = subst("blank", t, "line")
  return t
}

# 4.2.2 on the lines in LN[1..n], in place (writes never pass reads).
# Returns the new count; RCHANGED says whether anything collapsed.
function repeats(n,   i, j, k, r, cur) {
  RCHANGED = 0; k = 0
  for (i = 1; i <= n; i = j) {
    cur = LN[i]
    for (j = i + 1; j <= n && LN[j] == cur; j++) ;
    r = j - i
    if (r >= 3 && cur != "") { LN[++k] = cur; LN[++k] = "[skinflint: line above repeated " (r - 1) " more times]"; RCHANGED = 1 }
    else while (i < j) LN[++k] = LN[i++]
  }
  return k
}

function stamps(t,   n, L, K, i, j, k, out, r) {
  n = lines_of(t, L)
  for (i = 1; i <= n; i++)
    K[i] = match(L[i], /^\[?([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][T ][0-9][0-9]:[0-9][0-9]:[0-9][0-9]|[0-9][0-9]:[0-9][0-9]:[0-9][0-9])([.,][0-9]+)?(Z|[+-][0-9][0-9]:?[0-9][0-9])?\]?[ \t]*/) ? substr(L[i], RLENGTH + 1) : ""
  k = 0
  for (i = 1; i <= n; i = j) {
    if (K[i] == "") { out[++k] = L[i]; j = i + 1; continue }
    for (j = i + 1; j <= n && K[j] == K[i]; j++) ;
    r = j - i
    if (r >= 3) { out[++k] = L[i]; out[++k] = "[skinflint: " (r - 2) " more lines like this, differing only in timestamp]"; out[++k] = L[j - 1] }
    else while (i < j) out[++k] = L[i++]
  }
  return join(out, 1, k, "\n")
}

function is_frame(l) { return l ~ /^[ \t]+at [^ \t]/ || l ~ /^[ \t]*#[0-9]+[ \t]/ }
function is_pyframe(l) { return l ~ /^[ \t]+File "[^"]*", line [0-9]+/ }

function frames(t,   n, L, UK, i, u, US, UE, k, out, a, j, x) {
  n = lines_of(t, L)
  for (i = 1; i <= n; i++) {
    UK[i] = 0
    if (is_frame(L[i])) { UK[i] = 1; continue }
    if (is_pyframe(L[i])) {
      UK[i] = 1
      if (i < n && L[i + 1] ~ /^    / && !is_frame(L[i + 1]) && !is_pyframe(L[i + 1])) { UK[i] = 2; UK[i + 1] = -1; i++ }
    }
  }
  k = 0
  for (i = 1; i <= n; ) {
    if (UK[i] <= 0) { out[++k] = L[i]; i++; continue }
    u = 0
    for (j = i; j <= n && UK[j] > 0; j += UK[j]) { u++; US[u] = j; UE[u] = j + UK[j] - 1 }
    if (u >= 8) {
      for (a = 1; a <= 3; a++) for (x = US[a]; x <= UE[a]; x++) out[++k] = L[x]
      out[++k] = "[skinflint: " (u - 5) " stack frames omitted]"
      for (a = u - 1; a <= u; a++) for (x = US[a]; x <= UE[a]; x++) out[++k] = L[x]
    } else for (x = i; x < j; x++) out[++k] = L[x]
    i = j
  }
  return join(out, 1, k, "\n")
}

# Regexes are literals throughout the hot path: busybox awk recompiles a
# regex held in a string on every use (7x slower over 2000 lines).
function is_error(l,   lo) {
  lo = tolower(l)
  if (lo !~ /(^|[^a-z0-9_])(error|errors|err|fail|failed|failure|failures|failing|fatal|exception|traceback|panic|denied|refused|timeout|timed out|assert|assertion|assertionerror|segfault|segmentation fault|abort|aborted|critical|warning|warnings|undefined reference|cannot|can't|not found|no such file|unable to|unexpected)([^a-z0-9_]|$)/) return 0
  return lo !~ /(^|[^0-9])0 (errors?|failed|failures?|warnings?)|no (errors|failures|warnings)|(errors?|failures?|failed|warnings?)[ \t]*[:=][ \t]*0([^0-9]|$)/
}

function is_pass(l) {
  if (!(l ~ /^(ok|PASS|PASSED)([ \t:]|$)/ || l ~ /[ \t](ok|PASS|PASSED)$/ || l ~ /^[ \t]*(PASS|PASSED)[ \t]/ || index(l, CHECK))) return 0
  return !is_error(l)
}

function passes(t,   n, L, i, j, k, out, r) {
  n = lines_of(t, L)
  k = 0
  for (i = 1; i <= n; i = j) {
    if (!is_pass(L[i])) { out[++k] = L[i]; j = i + 1; continue }
    for (j = i + 1; j <= n && is_pass(L[j]); j++) ;
    r = j - i
    if (r >= 10) { out[++k] = L[i]; out[++k] = "[skinflint: " (r - 2) " more passing lines]"; out[++k] = L[j - 1] }
    else while (i < j) out[++k] = L[i++]
  }
  return join(out, 1, k, "\n")
}

function longlines(t,   n, L, i, h, z, hit) {
  n = lines_of(t, L)
  hit = 0
  for (i = 1; i <= n; i++) if (length(L[i]) > 4096) {
    h = head_bytes(L[i], 2048); z = tail_bytes(L[i], 512)
    L[i] = h " [skinflint: " (length(L[i]) - length(h) - length(z)) " bytes cut from this line] " z
    hit = 1
  }
  return hit ? join(L, 1, n, "\n") : t
}

# ---------- cuts (4.2.7, 4.2.8, 4.3) ----------

# The lines of t are in LN[1..n].
function cut_lines(t, orig, slot, n,   saved, a, b, head, tail, rescue) {
  saved = spill(orig, slot)
  a = HEAD + 1; b = n - TAIL
  head = join(LN, 1, HEAD, "\n"); tail = join(LN, b + 1, n, "\n")
  if (!VIEW) { head = finer(head); tail = finer(tail) }
  rescue = rescue_lines(t, a, b, n)
  return head "\n[skinflint: cut lines " a "-" b " of " n RESCUE "." saved "]" (rescue == "" ? "" : "\n" rescue) "\n" tail
}

# First 12 error lines of LN[a..b] with one line of context each. Sets
# RESCUE. The cut region is one substring of t, lower-cased once; if no error
# word occurs anywhere in it, that single search is the whole cost. Otherwise
# it is scanned in windows of about 16 KB of whole lines, and only lines in a
# window that holds an error word are checked one by one.
function rescue_lines(t, a, b, n,   st, en, i, mid, M, p, q, x, w, cnt, c, line, hits, e, sel, k, out, last) {
  RESCUE = ""
  st = 1; for (i = 1; i < a; i++) st += length(LN[i]) + 1
  en = length(t); for (i = n; i > b; i--) en -= length(LN[i]) + 1
  mid = tolower(substr(t, st, en - st + 1))
  if (mid !~ /err|fail|fatal|exception|traceback|panic|denied|refused|timeout|timed out|assert|segfault|segmentation fault|abort|critical|warning|undefined reference|cannot|can't|not found|no such file|unable to|unexpected/) return ""
  e = 0; line = a; M = length(mid)
  for (p = 1; p <= M && e <= 12; p = q + 1) {
    q = M + 1
    for (x = p + 16384; x <= M; x += 65536)
      if ((i = index(substr(mid, x, 65536), "\n"))) { q = x + i - 1; break }
    w = substr(mid, p, q - p)
    c = w; cnt = gsub(/\n/, "", c) + 1
    if (w ~ /err|fail|fatal|exception|traceback|panic|denied|refused|timeout|timed out|assert|segfault|segmentation fault|abort|critical|warning|undefined reference|cannot|can't|not found|no such file|unable to|unexpected/)
      for (i = line; i < line + cnt && e <= 12; i++) if (is_error(LN[i])) hits[++e] = i
    line += cnt
  }
  if (!e) return ""
  c = (e < 12 ? e : 12)
  RESCUE = "; kept " c " error " (c == 1 ? "line" : "lines") " below, with 1 line of context" (e > 12 ? "; the full text has more" : "")
  for (i = 1; i <= c; i++) {
    sel[hits[i]] = 1
    if (hits[i] - 1 >= a) sel[hits[i] - 1] = 1
    if (hits[i] + 1 <= b) sel[hits[i] + 1] = 1
  }
  k = 0; last = 0
  for (i = a; i <= b; i++) if (i in sel) {
    if (last && i > last + 1) out[++k] = "[...]"
    out[++k] = cut300(LN[i]); last = i
  }
  return join(out, 1, k, "\n")
}

function cut_bytes(t, orig, slot,   saved, x, h, z) {
  saved = spill(orig, slot)
  x = int(MAX / 2)
  h = head_bytes(t, x); z = tail_bytes(t, x)
  return h "\n[skinflint: cut " (length(t) - length(h) - length(z)) " bytes from the middle." saved "]\n" z
}

function spill(orig, slot,   p, lo) {
  if (ENVIRON["SKINFLINT_SPILL"] == "0" || TUID == "") return ""
  lo = tolower(orig)
  if (orig ~ SECRET1 || lo ~ SECRET2) return " Full text not saved: it looks like it holds a credential"
  if (!CAN_SPILL) return ""
  p = SPILL "/" SAFE_TOOL "-" TUID "-" slot ".txt"
  writefile(p, orig)
  SPILLED = 1
  return " Full text: " p " (search it rather than re-running)"
}

# ---------- stats (2) ----------

function add_stats(saved,   p, raw, s, e) {
  if (!CAN_WRITE) return
  p = STATE "/stats"
  s = 0; e = 0
  if (ENVIRON["SF_STATS"] == "1") {
    raw = readfile(p)
    if (raw !~ /^saved [0-9]+\nevents [0-9]+\n$/) return
    s = raw; sub(/^saved /, "", s); sub(/\n.*/, "", s)
    e = raw; sub(/^[^\n]*\nevents /, "", e); sub(/\n$/, "", e)
  }
  writefile(p, sprintf("saved %.0f\nevents %.0f\n", s + saved, e + 1))
}
