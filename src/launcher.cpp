// Player-facing launcher and settings dialog, plain Win32 (no SDK). CMakeLists.txt builds it twice into the
// project root:
//   "Dead or Alive 4.exe"           starts the game; the first plain launch (no doa4.toml) opens the settings first.
//   "Dead or Alive 4 Settings.exe"  (DOA4_SETTINGS_ONLY) the settings dialog only.
// doa4.toml in the project root (untracked) is the source of truth: the launcher copies it next to the game exe
// (the SDK reads <exe dir>\doa4.toml) before every launch, so rebuilds never lose it. Extra arguments pass through
// to the game and win over the flags below and over doa4.toml: & ".\Dead or Alive 4.exe" --resolution_scale=1

#define NOMINMAX
#include <windows.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <map>
#include <regex>
#include <stdexcept>
#include <string>

#include "launcher.h"

namespace fs = std::filesystem;
using Settings = std::map<std::string, std::string>;  // key -> value as written (text keeps its quotes)

static fs::path g_root;  // folder of this exe = project root
static Settings g_cfg;   // what the dialog edits

// Resolution presets: resolution_scale -> label. Only presets verified on DOA4 to the title screen are listed.
struct Preset { const char* scale; const wchar_t* label; int height; };
static const Preset kPresets[] = {{"1", L"720p (native, 1280x720)", 720},
                                  {"2", L"1440p (2560x1440)", 1440},
                                  {"3", L"4K (3840x2160)", 2160}};

static fs::path Toml() { return g_root / L"doa4.toml"; }
static std::wstring W(const std::string& s) {
  std::wstring w(MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), (int)w.size());
  return w;
}
static std::string Unquote(const std::string& v) { return v.size() >= 2 && v[0] == '"' ? v.substr(1, v.size() - 2) : v; }
static void Message(const std::wstring& text, UINT icon) {
  MessageBoxW(nullptr, text.c_str(), L"Dead or Alive 4", MB_OK | icon);
}

// One "key = value" line: bool, integer or a plain double-quoted string. That is all the dialog writes.
static Settings ReadToml() {
  static const std::regex line_rx(R"(^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(true|false|-?\d+|"[^"\\]*")\s*(#.*)?$)");
  static const std::regex blank_rx(R"(^\s*(#.*)?$)");
  Settings v;
  std::ifstream f(Toml());
  std::string line;
  std::smatch m;
  for (int n = 1; std::getline(f, line); n++) {
    if (!line.empty() && line.back() == '\r') line.pop_back();
    if (std::regex_match(line, blank_rx)) continue;
    if (!std::regex_match(line, m, line_rx))
      throw std::runtime_error("line " + std::to_string(n) + ": '" + line +
                               "' is not key = true, false, a number or text in double quotes");
    v[m[1]] = m[2];
  }
  if (v.count("resolution_scale") &&
      std::none_of(std::begin(kPresets), std::end(kPresets), [&](auto& p) { return v["resolution_scale"] == p.scale; }))
    throw std::runtime_error("resolution_scale = " + v["resolution_scale"] + " (allowed: 1, 2, 3)");
  if (v.count("gamertag") && (Unquote(v["gamertag"]).empty() || Unquote(v["gamertag"]).size() > 15))
    throw std::runtime_error("gamertag must be 1-15 characters");
  return v;
}

static bool WriteToml(Settings v) {
  std::ofstream f(Toml(), std::ios::trunc);
  f << "# Dead or Alive 4 settings, written by \"Dead or Alive 4 Settings.exe\".\n"
       "# \"Dead or Alive 4.exe\" copies this file next to the game exe before every launch.\n";
  for (const char* k : {"resolution_scale", "fullscreen", "gamertag", "audio_mute", "skip_boot_movies"}) {
    f << k << " = " << v[k] << "\n";
    v.erase(k);
  }
  for (auto& [k, val] : v) f << k << " = " << val << "\n";  // keep any other cvar someone added by hand
  return bool(f.flush());
}

// Physical height of the tallest monitor (display modes are not DPI-scaled).
static int TallestMonitor() {
  int h = 0;
  DISPLAY_DEVICEW d{sizeof d};
  for (DWORD i = 0; EnumDisplayDevicesW(nullptr, i, &d, 0); i++) {
    DEVMODEW mode{};
    mode.dmSize = sizeof mode;
    if ((d.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) &&
        EnumDisplaySettingsW(d.DeviceName, ENUM_CURRENT_SETTINGS, &mode))
      h = std::max(h, (int)mode.dmPelsHeight);
  }
  return h;
}

static INT_PTR CALLBACK SettingsProc(HWND dlg, UINT msg, WPARAM wp, LPARAM) {
  auto check = [&](int id, const char* key) { CheckDlgButton(dlg, id, g_cfg[key] == "true" ? BST_CHECKED : BST_UNCHECKED); };
  auto read = [&](int id, const char* key) { g_cfg[key] = IsDlgButtonChecked(dlg, id) ? "true" : "false"; };
  if (msg == WM_INITDIALOG) {
    HWND res = GetDlgItem(dlg, IDC_RES);
    for (auto& p : kPresets) {
      int i = (int)SendMessageW(res, CB_ADDSTRING, 0, (LPARAM)p.label);
      if (g_cfg["resolution_scale"] == p.scale) SendMessageW(res, CB_SETCURSEL, i, 0);
    }
    SetDlgItemTextW(dlg, IDC_MONITOR, (L"Your tallest monitor: " + std::to_wstring(TallestMonitor()) +
                                       L"p. A GPU without tiled resources stays at 720p.").c_str());
    check(IDC_FULL, "fullscreen");
    check(IDC_MUTE, "audio_mute");
    check(IDC_INTRO, "skip_boot_movies");
    SendDlgItemMessageW(dlg, IDC_TAG, EM_LIMITTEXT, 15, 0);
    SetDlgItemTextW(dlg, IDC_TAG, W(Unquote(g_cfg["gamertag"])).c_str());
    return TRUE;
  }
  if (msg != WM_COMMAND) return FALSE;
  int id = LOWORD(wp);
  if (id == IDCANCEL) return EndDialog(dlg, IDCANCEL);
  if (id != IDOK && id != IDC_PLAY) return FALSE;
  wchar_t buf[64]{};
  GetDlgItemTextW(dlg, IDC_TAG, buf, 64);
  std::wstring tag = buf;
  tag.erase(0, tag.find_first_not_of(L' '));
  tag.erase(tag.find_last_not_of(L' ') + 1);
  // Plain ASCII without " or \ so it stays a valid TOML string.
  if (tag.empty() || tag.size() > 15 ||
      std::any_of(tag.begin(), tag.end(), [](wchar_t c) { return c < 0x20 || c > 0x7E || c == L'"' || c == L'\\'; })) {
    MessageBoxW(dlg, L"Gamertag: 1-15 plain ASCII characters, no \" or \\.", L"Dead or Alive 4", MB_OK | MB_ICONWARNING);
    SetFocus(GetDlgItem(dlg, IDC_TAG));
    return TRUE;
  }
  g_cfg["gamertag"] = "\"" + std::string(tag.begin(), tag.end()) + "\"";
  g_cfg["resolution_scale"] = kPresets[SendDlgItemMessageW(dlg, IDC_RES, CB_GETCURSEL, 0, 0)].scale;
  read(IDC_FULL, "fullscreen");
  read(IDC_MUTE, "audio_mute");
  read(IDC_INTRO, "skip_boot_movies");
  if (!WriteToml(g_cfg)) {
    MessageBoxW(dlg, (L"Could not write " + Toml().wstring()).c_str(), L"Dead or Alive 4", MB_OK | MB_ICONERROR);
    return TRUE;
  }
  return EndDialog(dlg, id);
}

// Returns the button that closed the dialog: IDOK (saved), IDC_PLAY (saved, start the game) or IDCANCEL.
static INT_PTR ShowSettings() {
  // Defaults: the largest preset that fits the tallest monitor, fullscreen, sound on, no intro movie
  // (skip_boot_movies, src/doa4_app.h).
  int monitor = TallestMonitor();
  g_cfg = {{"resolution_scale", "1"}, {"fullscreen", "true"},
           {"audio_mute", "false"}, {"gamertag", "\"User\""}, {"skip_boot_movies", "true"}};
  for (auto& p : kPresets)
    if (p.height <= monitor) g_cfg["resolution_scale"] = p.scale;
  if (fs::exists(Toml())) {
    try {
      for (auto& [k, v] : ReadToml()) g_cfg[k] = v;
    } catch (std::exception& e) {
      Message(L"doa4.toml is invalid (" + W(e.what()) + L"); starting from defaults.", MB_ICONWARNING);
    }
  }
  return DialogBoxW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDD_SETTINGS), nullptr, SettingsProc);
}

static int Launch(const std::wstring& extra) {
  fs::path game = (g_root / DOA4_GAME_EXE).make_preferred();
  if (!fs::exists(game)) {
    Message(L"The game is not built yet (" + game.wstring() + L" is missing).\n\nDouble-click setup.bat (see README.md).",
            MB_ICONERROR);
    return 1;
  }
  // Copy doa4.toml next to the game exe, or remove a stale copy when it is missing or invalid, so the game starts
  // on defaults.
  std::error_code ec;
  fs::path copy = game.parent_path() / L"doa4.toml";
  fs::remove(copy, ec);
  if (fs::exists(Toml())) {
    try {
      ReadToml();
      fs::copy_file(Toml(), copy, ec);
    } catch (std::exception& e) {
      Message(L"doa4.toml is invalid (" + W(e.what()) +
                  L").\n\nStarting with default settings; fix them in Dead or Alive 4 Settings.",
              MB_ICONWARNING);
    }
  }
  auto quoted = [](const fs::path& p) { return L"\"" + p.wstring() + L"\""; };
  std::wstring cmd = quoted(game) +
      // Required: the game does not work right without these.
      //   Extracted disc (setup.bat puts it here).
      L" --game_data_root=" + quoted(g_root / L"original rom" / L"extracted") +
      //   Buffers above 256 MB so the game's "offset < base -> relocate" check works (Brad/Hayabusa motion, SDK 0015).
      L" --guest_low_reserve_mb=256"
      //   CPU reads of GPU resolves: replay-camera autofocus and photo encode (SDK 0020); ~40 fps vs ~16 with fast.
      L" --readback_resolve=lazy"
      // Crash reports: a crash writes crashes\<timestamp>\ (logs, stack, last frame); attach it to a bug report.
      L" --crash_bundle_dir=" + quoted(g_root / L"crashes") + L" --flight_recorder=true " + extra;
  STARTUPINFOW si{sizeof si};
  PROCESS_INFORMATION pi{};
  // Start in the project root so input_scripts/ (--input_script=NAME, --use_input_rec) resolves here.
  if (!CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, 0, nullptr, g_root.c_str(), &si, &pi)) {
    Message(L"Could not start " + game.wstring() + L" (error " + std::to_wstring(GetLastError()) + L").", MB_ICONERROR);
    return 1;
  }
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return 0;
}

// The command line after this exe's own path.
static std::wstring Args() {
  const wchar_t* p = GetCommandLineW();
  if (*p == L'"') {
    p = wcschr(p + 1, L'"');
    p = p ? p + 1 : L"";
  } else {
    while (*p && *p != L' ' && *p != L'\t') p++;
  }
  while (*p == L' ' || *p == L'\t') p++;
  return p;
}

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
  wchar_t self[4096];
  GetModuleFileNameW(nullptr, self, 4096);
  g_root = fs::path(self).parent_path();
#ifdef DOA4_SETTINGS_ONLY
  return ShowSettings() == IDC_PLAY ? Launch(L"") : 0;
#else
  std::wstring args = Args();
  if (args.empty() && !fs::exists(Toml()) && ShowSettings() != IDC_PLAY) return 0;
  return Launch(args);
#endif
}
