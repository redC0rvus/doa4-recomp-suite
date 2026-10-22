// doa4 - ReXGlue Recompiled Project
//
// Customize your app by overriding virtual hooks from rex::ReXApp.

#pragma once

#include <rex/filesystem/devices/host_path_device.h>
#include <rex/filesystem/vfs.h>
#include <rex/rex_app.h>
#include <rex/runtime.h>
#include <rex/cvar.h>
#include <rex/system/crash_bundle.h>

#include "input_scripts.h"

// Only main.cpp includes this header, so defining the cvar here is safe.
REXCVAR_DEFINE_BOOL(mount_cache, true, "Storage", "Mount cache:\\ as a writable host folder");
REXCVAR_DEFINE_BOOL(skip_boot_movies, true, "Video",
                    "Hide the Team Ninja boot logo movie (movie/ninja_vi_hd.sfd) so the game skips it");
REXCVAR_DEFINE_STRING(save_checkpoint_dir, "", "Storage",
                      "Copy the save here whenever the game writes it (empty = off)");
REXCVAR_DECLARE(bool, mnk_mode);  // SDK keyboard-as-pad driver; forced on in OnPreSetup

#include <algorithm>
#include <chrono>
#include <ctime>
#include <thread>

// Copy the save folder to <dir>/<timestamp>/ each time the game finishes
// writing it, keeping the newest 20. Same layout as tools/save.ps1 snapshots.
// Copies are at least 60 s
// apart (20 copies >= 20 min of play); the latest write is still copied after the gap.
// ponytail: 2 s mtime poll; a write counts as finished once a poll sees no change.
inline void StartSaveCheckpoints(std::filesystem::path save, std::filesystem::path dir) {
  namespace fs = std::filesystem;
  auto newest = [save] {
    fs::file_time_type t{};
    std::error_code ec;
    for (auto it = fs::recursive_directory_iterator(save, ec); !ec && it != fs::end(it);
         it.increment(ec))
      t = std::max(t, it->last_write_time(ec));
    return t;
  };
  std::thread([=] {
    auto seen = newest(), pending = seen;
    auto last_copy = std::chrono::steady_clock::now() - std::chrono::minutes(1);
    for (;;) {
      std::this_thread::sleep_for(std::chrono::seconds(2));
      auto now = newest();
      if (now != pending) {  // still being written
        pending = now;
        continue;
      }
      if (now == seen) continue;
      if (std::chrono::steady_clock::now() - last_copy < std::chrono::seconds(60)) continue;
      seen = now;
      last_copy = std::chrono::steady_clock::now();
      auto t = std::time(nullptr);
      std::tm tm{};
      localtime_s(&tm, &t);
      char stamp[32];
      std::strftime(stamp, sizeof(stamp), "%Y%m%d-%H%M%S", &tm);
      std::error_code ec;
      fs::create_directories(dir, ec);
      fs::copy(save, dir / stamp, fs::copy_options::recursive, ec);
      REXLOG_INFO("Save checkpoint: {}{}", (dir / stamp).string(),
                  ec ? " (FAILED: " + ec.message() + ")" : "");
      std::vector<fs::path> all;
      for (auto& e : fs::directory_iterator(dir, ec)) all.push_back(e.path());
      std::sort(all.begin(), all.end());  // timestamp names sort oldest first
      for (size_t i = 0; i + 20 < all.size(); ++i) fs::remove_all(all[i], ec);
    }
  }).detach();
}


// Drop the boot logo movie from the game-data tree (in memory only; the host file is untouched).
// The VFS opens files via parent->GetChild(), so it has to go from the parent's child list.
// ponytail: one hard-coded name; make it a list if more boot movies need hiding.
struct EntryKids : rex::filesystem::Entry {  // only used to reach protected children_
  static void Hide(rex::filesystem::Entry* dir, std::string_view name) {
    auto& kids = static_cast<EntryKids*>(dir)->children_;
    std::erase_if(kids, [&](auto& e) {
      return e->name().size() == name.size() &&
             std::equal(name.begin(), name.end(), e->name().begin(),
                        [](char a, char b) { return std::tolower((unsigned char)a) == std::tolower((unsigned char)b); });
    });
  }
};

class Doa4App : public rex::ReXApp {
 public:
  using rex::ReXApp::ReXApp;

  static std::unique_ptr<rex::ui::WindowedApp> Create(
      rex::ui::WindowedAppContext& ctx) {
    return std::unique_ptr<Doa4App>(new Doa4App(ctx, "doa4",
        PPCImageConfig));
  }

  // Override virtual hooks for customization:
  // void OnPostInitLogging() override {}
  // Default to the Xenos GPU plugin; --gpu_plugin=<name> still overrides.
  void OnPreSetup(rex::RuntimeConfig& config) override {
    if (config.gpu_plugin.empty()) config.gpu_plugin = "xenos";
    // Keyboard always works alongside pads: the SDK merges it into player 1 (buttons OR'd, the
    // larger stick wins), so there is nothing to choose. Overrides an old doa4.toml "mnk_mode = false".
    REXCVAR_SET(mnk_mode, true);
  }
  // void OnLoadXexImage(std::string& xex_image) override {}
  // void OnPostLoadXexImage() override {}
  // Mount cache:\ as a writable host folder (the SDK leaves it unmounted;
  // Xenia's --mount_cache does the same thing).
  void OnPostSetup() override {
    // Crash bundle (summary, log tail, dump, save copy, last frame) on any crash.
    rex::crash::Install(user_data_root_ / "B13EBABEBABEBABE");
    input_scripts::Install(runtime());  // --input_script, _play.txt, F9 recording (--use_input_rec)
    if (!REXCVAR_GET(save_checkpoint_dir).empty())
      StartSaveCheckpoints(user_data_root_ / "B13EBABEBABEBABE" / "544307D1",
                           REXCVAR_GET(save_checkpoint_dir));
    if (REXCVAR_GET(skip_boot_movies)) {
      auto* dir = runtime()->file_system()->ResolvePath("game:\\movie");
      if (dir) EntryKids::Hide(dir, "ninja_vi_hd.sfd");
      else REXLOG_WARN("skip_boot_movies: movie dir not found");
    }
    if (!REXCVAR_GET(mount_cache)) return;
    auto host = cache_root_ / "cache_partition";
    std::filesystem::create_directories(host);
    auto* vfs = runtime()->file_system();
    auto dev = std::make_unique<rex::filesystem::HostPathDevice>("\\CACHE", host, false);
    if (dev->Initialize() && vfs->RegisterDevice(std::move(dev))) {
      vfs->RegisterSymbolicLink("cache:", "\\CACHE");
    }
  }
  void OnCreateDialogs(rex::ui::ImGuiDrawer* drawer) override { input_scripts::CreateOverlay(drawer); }
  // std::unique_ptr<rex::ui::ImGuiDialog> CreateAchievementsOverlay() override;
  // std::unique_ptr<rex::ui::AchievementNotificationDialog>
  // CreateAchievementNotificationDialog() override;
  void OnShutdown() override { input_scripts::Shutdown(); }
  void OnConfigurePaths(rex::PathConfig& paths) override {
    cache_root_ = paths.cache_root;
    user_data_root_ = paths.user_data_root;
  }

 private:
  std::filesystem::path cache_root_;
  std::filesystem::path user_data_root_;
};
