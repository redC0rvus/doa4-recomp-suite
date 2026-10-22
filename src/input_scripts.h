// Dev input scripts for ReXGlue recomps: record pad-0 input with F9, replay it from launch or into the running game.
// Needs the SDK pad-filter hook (InputSystem::SetPadFilter). Include once from the app header, then:
//   OnCreateDialogs(drawer): input_scripts::CreateOverlay(drawer)   (overlay + F9, only with --use_input_rec)
//   OnPostSetup():           input_scripts::Install(runtime())      (pad filter: record, replay, _play.txt)
//   OnShutdown():            input_scripts::Shutdown()
//
// Scripts are input_scripts/NAME.txt (relative to the working directory), one step per line, '#' starts a comment:
//   wait MS | press BTN [MS] | hold AXIS VALUE MS | down BTN | up BTN | AXIS VALUE
// Buttons UP DOWN LEFT RIGHT START BACK LS RS LB RB GUIDE A B X Y; axes lt rt lx ly rx ry. Waits are relative to the
// previous step: --input_script counts from launch, input_scripts/_play.txt from when it is picked up (polled every
// 1 s, then deleted). An F9 recording's first wait counts from F9, so it plays into the game's current state.
#pragma once

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include <imgui.h>

#include <rex/cvar.h>
#include <rex/input/input_system.h>
#include <rex/logging.h>
#include <rex/runtime.h>
#include <rex/ui/imgui_dialog.h>
#include <rex/ui/imgui_drawer.h>
#include <rex/ui/keybinds.h>

REXCVAR_DEFINE_STRING(input_script, "", "Input",
                      "Dev: play an input script on pad 0 over live input from launch; logs 'input_script: done' at "
                      "the end; a bare NAME means input_scripts/NAME.txt");
REXCVAR_DEFINE_BOOL(use_input_rec, false, "Input",
                    "Dev: F9 records pad-0 input with an on-screen status, then asks for a name "
                    "(saved to input_scripts/NAME.txt)");

namespace input_scripts {

using rex::input::X_INPUT_GAMEPAD;

enum class RecState { kIdle, kRecording, kStopped };  // kStopped = the name prompt is open

inline const auto g_t0 = std::chrono::steady_clock::now();
constexpr const char* kScriptDir = "input_scripts";
constexpr const char* kRecordingPath = "input_scripts/_recording.txt";
constexpr const char* kPlayPath = "input_scripts/_play.txt";

struct PadState {
  uint16_t buttons = 0;
  int axes[6] = {};  // lt rt lx ly rx ry
};

constexpr struct {
  const char* name;
  uint16_t mask;
} kButtons[] = {{"UP", 0x0001},    {"DOWN", 0x0002}, {"LEFT", 0x0004}, {"RIGHT", 0x0008}, {"START", 0x0010},
                {"BACK", 0x0020},  {"LS", 0x0040},   {"RS", 0x0080},   {"LB", 0x0100},    {"RB", 0x0200},
                {"GUIDE", 0x0400}, {"A", 0x1000},    {"B", 0x2000},    {"X", 0x4000},     {"Y", 0x8000}};
constexpr const char* kAxes[6] = {"lt", "rt", "lx", "ly", "rx", "ry"};

struct State {
  std::mutex mutex;
  bool loaded = false;
  // F9 recorder
  RecState rec_state = RecState::kIdle;
  FILE* record = nullptr;
  PadState recorded;
  int64_t rec_start = 0;
  int64_t rec_last = 0;
  int rec_steps = 0;
  // replay: (ms since launch, "down X" / "lx V") applied in order
  std::string name;
  std::vector<std::pair<int64_t, std::string>> events;
  size_t next = 0;
  PadState scripted;
  int64_t next_poll = 0;
};

inline State& S() {
  static State s;
  return s;
}

inline int64_t NowMs() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(std::chrono::steady_clock::now() - g_t0).count();
}

// ponytail: bare name -> input_scripts/NAME.txt relative to the working directory (run.bat starts in the project root).
inline std::string ScriptPath(const std::string& v) {
  return !v.empty() && v.find_first_of("/\\.") == std::string::npos ? std::string(kScriptDir) + "/" + v + ".txt"
                                                                       : v;
}

inline bool IsAxis(const std::string& a) {
  return std::find_if(std::begin(kAxes), std::end(kAxes), [&](const char* x) { return a == x; }) != std::end(kAxes);
}

// Live state for recording, with resting-stick/trigger noise clamped to 0 (XInput dead zones).
inline PadState ToPad(const X_INPUT_GAMEPAD& g) {
  PadState p;
  p.buttons = g.buttons;
  p.axes[0] = g.left_trigger;
  p.axes[1] = g.right_trigger;
  p.axes[2] = g.thumb_lx;
  p.axes[3] = g.thumb_ly;
  p.axes[4] = g.thumb_rx;
  p.axes[5] = g.thumb_ry;
  for (int i = 0; i < 6; ++i) {
    if (std::abs(p.axes[i]) < (i < 2 ? 30 : 8000)) {
      p.axes[i] = 0;
    }
  }
  return p;
}

inline void ApplyEvent(PadState& pad, const std::string& rest) {
  std::istringstream in(rest);
  std::string a, b;
  in >> a >> b;
  if (a == "down" || a == "up") {
    for (auto& btn : kButtons) {
      if (b == btn.name) {
        pad.buttons = a == "down" ? (pad.buttons | btn.mask) : (pad.buttons & ~btn.mask);
        return;
      }
    }
  } else {
    for (int i = 0; i < 6; ++i) {
      if (a == kAxes[i]) {
        pad.axes[i] = std::atoi(b.c_str());
        return;
      }
    }
  }
  REXLOG_WARN("input_script: bad event '{}'", rest);
}

inline void StartScript(State& s, const std::string& path, int64_t t) {
  std::ifstream in(path);
  if (!in.is_open()) {
    REXLOG_WARN("input_script: cannot open '{}'", path);
    return;
  }
  s.events.clear();
  s.next = 0;
  s.scripted = {};
  s.name = path;
  std::string line;
  while (std::getline(in, line)) {
    std::istringstream ls(line.substr(0, line.find('#')));
    std::string op, a, b, c;
    ls >> op >> a >> b >> c;
    if (op.empty()) {
      continue;
    } else if (op == "wait") {
      t += std::atoll(a.c_str());
    } else if (op == "press") {
      s.events.emplace_back(t, "down " + a);
      t += b.empty() ? 60 : std::atoll(b.c_str());
      s.events.emplace_back(t, "up " + a);
    } else if (op == "hold") {
      s.events.emplace_back(t, a + " " + b);
      t += std::atoll(c.c_str());
      s.events.emplace_back(t, a + " 0");
    } else {
      s.events.emplace_back(t, op + " " + a);
    }
  }
  REXLOG_INFO("input_script: playing '{}' ({} events)", path, s.events.size());
}

// Turns "down X / wait N / up X" into "press X N" and "AXIS V / wait N / AXIS 0" into "hold AXIS V N".
inline std::vector<std::string> CompactRecording(const std::string& path) {
  std::vector<std::vector<std::string>> rows;
  std::vector<std::string> out;
  std::ifstream in(path);
  std::string line;
  while (std::getline(in, line)) {
    if (line.starts_with("#")) {
      out.push_back(line);
      continue;
    }
    std::istringstream ls(line);
    std::vector<std::string> tok;
    for (std::string t; ls >> t;) {
      tok.push_back(t);
    }
    if (tok.size() == 2) {
      rows.push_back(tok);
    }
  }
  for (size_t i = 0; i < rows.size(); ++i) {
    if (i + 2 < rows.size() && rows[i + 1][0] == "wait") {
      const auto &a = rows[i], &c = rows[i + 2];
      if (a[0] == "down" && c[0] == "up" && a[1] == c[1]) {
        out.push_back("press " + a[1] + " " + rows[i + 1][1]);
        i += 2;
        continue;
      }
      if (IsAxis(a[0]) && a[1] != "0" && c[0] == a[0] && c[1] == "0") {
        out.push_back("hold " + a[0] + " " + a[1] + " " + rows[i + 1][1]);
        i += 2;
        continue;
      }
    }
    out.push_back(rows[i][0] + " " + rows[i][1]);
  }
  return out;
}

inline void WriteRecordStep(State& s, int64_t now, const std::string& step) {
  if (now > s.rec_last) {
    std::fprintf(s.record, "wait %lld\n", static_cast<long long>(now - s.rec_last));
    s.rec_last = now;
  }
  std::fprintf(s.record, "%s\n", step.c_str());
  ++s.rec_steps;
}

// Writes every live change as a step; called with an empty state on stop, so recordings end fully released.
inline void RecordState(State& s, int64_t now, const PadState& live) {
  for (auto& btn : kButtons) {
    if ((live.buttons ^ s.recorded.buttons) & btn.mask) {
      WriteRecordStep(s, now, std::string((live.buttons & btn.mask) ? "down " : "up ") + btn.name);
    }
  }
  for (int i = 0; i < 6; ++i) {
    if (live.axes[i] != s.recorded.axes[i]) {
      WriteRecordStep(s, now, std::string(kAxes[i]) + " " + std::to_string(live.axes[i]));
    }
  }
  std::fflush(s.record);
  s.recorded = live;
}

// Pad filter for user 0: records the live state, then merges the script on top (buttons OR, a non-zero scripted
// axis wins). While the name prompt is open the pad reads as idle, so typing the name does not drive the game.
inline void Filter(uint32_t user_index, X_INPUT_GAMEPAD& g) {
  if (user_index != 0) {
    return;
  }
  auto& s = S();
  std::lock_guard<std::mutex> lock(s.mutex);
  int64_t now = NowMs();
  if (!s.loaded) {
    s.loaded = true;
    if (!REXCVAR_GET(input_script).empty()) {
      StartScript(s, ScriptPath(REXCVAR_GET(input_script)), 0);
    }
  }
  // ponytail: one stat per second for the live trigger; a file watcher if that ever shows up in a profile.
  if (now >= s.next_poll) {
    s.next_poll = now + 1000;
    std::error_code ec;
    if (std::filesystem::exists(kPlayPath, ec)) {
      StartScript(s, kPlayPath, now);
      std::filesystem::remove(kPlayPath, ec);
    }
  }
  if (s.rec_state == RecState::kStopped) {
    g = {};
    return;
  }
  if (s.record) {
    RecordState(s, now, ToPad(g));
  }
  if (s.name.empty()) {
    return;
  }
  while (s.next < s.events.size() && s.events[s.next].first <= now) {
    ApplyEvent(s.scripted, s.events[s.next++].second);
  }
  if (s.next == s.events.size()) {
    REXLOG_INFO("input_script: done '{}' at {} ms", s.name, now);
    s.name.clear();
    s.scripted = {};
    return;
  }
  const PadState& p = s.scripted;
  g.buttons = static_cast<uint16_t>(g.buttons) | p.buttons;
  if (p.axes[0]) g.left_trigger = static_cast<uint8_t>(p.axes[0]);
  if (p.axes[1]) g.right_trigger = static_cast<uint8_t>(p.axes[1]);
  if (p.axes[2]) g.thumb_lx = static_cast<int16_t>(p.axes[2]);
  if (p.axes[3]) g.thumb_ly = static_cast<int16_t>(p.axes[3]);
  if (p.axes[4]) g.thumb_rx = static_cast<int16_t>(p.axes[4]);
  if (p.axes[5]) g.thumb_ry = static_cast<int16_t>(p.axes[5]);
}

inline void ToggleRecording() {
  auto& s = S();
  std::lock_guard<std::mutex> lock(s.mutex);
  int64_t now = NowMs();
  if (s.rec_state == RecState::kIdle) {
    std::error_code ec;
    std::filesystem::create_directories(kScriptDir, ec);
    s.record = std::fopen(kRecordingPath, "w");
    if (!s.record) {
      REXLOG_WARN("input_record: cannot open '{}'", kRecordingPath);
      return;
    }
    s.recorded = {};
    s.rec_start = now;
    s.rec_last = now;
    s.rec_steps = 0;
    s.rec_state = RecState::kRecording;
    REXLOG_INFO("input_record: recording to '{}'", kRecordingPath);
  } else if (s.rec_state == RecState::kRecording) {
    RecordState(s, now, {});
    std::fclose(s.record);
    s.record = nullptr;
    s.rec_state = RecState::kStopped;
    REXLOG_INFO("input_record: stopped, {} steps", s.rec_steps);
  }
}

// Saves the stopped recording as input_scripts/NAME.txt (empty name discards it); returns the path written.
inline std::string FinishRecording(const std::string& name) {
  auto& s = S();
  std::lock_guard<std::mutex> lock(s.mutex);
  if (s.rec_state != RecState::kStopped) {
    return {};
  }
  s.rec_state = RecState::kIdle;
  std::error_code ec;
  if (name.empty()) {
    std::filesystem::remove(kRecordingPath, ec);
    REXLOG_INFO("input_record: discarded");
    return {};
  }
  const std::string path = ScriptPath(name);
  const auto lines = CompactRecording(kRecordingPath);
  std::ofstream out(path);
  for (auto& line : lines) {
    out << line << '\n';
  }
  out.close();
  if (!out) {
    REXLOG_WARN("input_record: cannot write '{}' (kept {})", path, kRecordingPath);
    return {};
  }
  std::filesystem::remove(kRecordingPath, ec);
  REXLOG_INFO("input_record: saved '{}'", path);
  return path;
}

// Top-left status line; a stopped F9 recording asks for a name.
class Dialog final : public rex::ui::ImGuiDialog {
 public:
  explicit Dialog(rex::ui::ImGuiDrawer* drawer) : ImGuiDialog(drawer) {}

 protected:
  void OnDraw(ImGuiIO& io) override {
    RecState state;
    int64_t rec_ms;
    int rec_steps;
    std::string script;
    size_t pos, len;
    {
      auto& s = S();
      std::lock_guard<std::mutex> lock(s.mutex);
      state = s.rec_state;
      rec_ms = state == RecState::kRecording ? NowMs() - s.rec_start : 0;
      rec_steps = s.rec_steps;
      script = s.name;
      pos = s.next;
      len = s.events.size();
    }
    // Default ImGui text is tiny at 1440p; scale from a 720p baseline.
    ImGui::PushFont(nullptr, ImGui::GetStyle().FontSizeBase * std::max(1.0f, io.DisplaySize.y / 720.0f));
    ImGui::SetNextWindowPos(ImVec2(10, 10), ImGuiCond_Always);
    ImGui::SetNextWindowBgAlpha(0.6f);
    constexpr ImGuiWindowFlags kFlags = ImGuiWindowFlags_NoDecoration | ImGuiWindowFlags_AlwaysAutoResize |
                                        ImGuiWindowFlags_NoInputs | ImGuiWindowFlags_NoNav |
                                        ImGuiWindowFlags_NoSavedSettings | ImGuiWindowFlags_NoFocusOnAppearing;
    if (ImGui::Begin("##input_rec", nullptr, kFlags)) {
      if (state == RecState::kRecording) {
        ImGui::TextColored(ImVec4(1.0f, 0.3f, 0.3f, 1.0f), "REC %d:%02d  %d steps  (F9 stop)",
                           static_cast<int>(rec_ms / 60000), static_cast<int>(rec_ms / 1000 % 60), rec_steps);
      } else if (state == RecState::kStopped) {
        ImGui::TextUnformatted("Recording stopped");
      } else {
        ImGui::TextDisabled("F9: record input");
      }
      if (!script.empty()) {
        ImGui::Text("Playing %s  %zu/%zu", script.c_str(), pos, len);
      }
      if (!message_.empty() && ImGui::GetTime() - message_time_ < 4.0) {
        ImGui::TextColored(ImVec4(0.4f, 1.0f, 0.4f, 1.0f), "%s", message_.c_str());
      }
    }
    ImGui::End();
    if (state == RecState::kStopped) {
      DrawPrompt();
    }
    ImGui::PopFont();
  }

 private:
  static constexpr const char* kPopup = "Save input recording";

  // Keeps names to [A-Za-z0-9_-], so NAME always maps to input_scripts/NAME.txt.
  static int FilterChar(ImGuiInputTextCallbackData* d) {
    const auto c = d->EventChar;
    return !(c < 128 && (std::isalnum(static_cast<int>(c)) || c == '_' || c == '-'));
  }

  void DrawPrompt() {
    if (!ImGui::IsPopupOpen(kPopup)) {
      ImGui::OpenPopup(kPopup);
      name_[0] = '\0';
      focus_ = true;
    }
    ImGui::SetNextWindowPos(ImGui::GetMainViewport()->GetCenter(), ImGuiCond_Appearing, ImVec2(0.5f, 0.5f));
    if (!ImGui::BeginPopupModal(kPopup, nullptr, ImGuiWindowFlags_AlwaysAutoResize)) {
      return;
    }
    ImGui::TextUnformatted("Name (saved to input_scripts/NAME.txt):");
    if (focus_) {
      ImGui::SetKeyboardFocusHere();
      focus_ = false;
    }
    const bool enter = ImGui::InputText("##name", name_, sizeof(name_),
                                        ImGuiInputTextFlags_EnterReturnsTrue | ImGuiInputTextFlags_CallbackCharFilter,
                                        FilterChar);
    const std::string name = name_;
    if (!name.empty() && std::filesystem::exists(ScriptPath(name))) {
      ImGui::TextColored(ImVec4(1.0f, 0.8f, 0.3f, 1.0f), "Overwrites the existing script");
    }
    ImGui::BeginDisabled(name.empty());
    const bool save = ImGui::Button("Save") || (enter && !name.empty());
    ImGui::EndDisabled();
    ImGui::SameLine();
    const bool cancel = ImGui::Button("Cancel") || ImGui::IsKeyPressed(ImGuiKey_Escape);
    if (save || cancel) {
      pending_ = save ? 1 : 2;
    }
    // Finish only once Enter/Escape are up: the pad comes back with the prompt, and a held Enter would reach the
    // game as START through the keyboard pad.
    if (pending_ && !ImGui::IsKeyDown(ImGuiKey_Enter) && !ImGui::IsKeyDown(ImGuiKey_KeypadEnter) &&
        !ImGui::IsKeyDown(ImGuiKey_Escape)) {
      const std::string path = FinishRecording(pending_ == 1 ? name : "");
      message_ = pending_ == 2 ? "Recording discarded" : path.empty() ? "Save failed, see the log" : "Saved " + path;
      message_time_ = ImGui::GetTime();
      pending_ = 0;
      ImGui::CloseCurrentPopup();
    }
    ImGui::EndPopup();
  }

  char name_[64] = {};
  bool focus_ = false;
  int pending_ = 0;  // 1 save, 2 cancel, waiting for the key release
  std::string message_;
  double message_time_ = 0;
};

inline std::unique_ptr<Dialog>& DialogSlot() {
  static std::unique_ptr<Dialog> d;
  return d;
}

inline void CreateOverlay(rex::ui::ImGuiDrawer* drawer) {
  if (!REXCVAR_GET(use_input_rec) || !drawer) {
    return;
  }
  DialogSlot() = std::make_unique<Dialog>(drawer);
  rex::ui::RegisterBind("bind_input_rec", "F9", "Start/stop input recording (--use_input_rec)",
                        [] { ToggleRecording(); });
}

inline void Install(rex::Runtime* runtime) {
  if (auto* input = runtime ? static_cast<rex::input::InputSystem*>(runtime->input_system()) : nullptr) {
    input->SetPadFilter(Filter);
  }
}

inline void Shutdown() {
  rex::ui::UnregisterBind("bind_input_rec");
  DialogSlot().reset();
}

}  // namespace input_scripts
