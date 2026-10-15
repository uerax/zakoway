#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter_windows.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {

// Calculate adaptive default window dimensions and centered position.
// Downscales by one step relative to the primary monitor's work area
// (excluding taskbar) and keeps a 16:9 aspect ratio.
void CalculateDefaultWindowBounds(Win32Window::Point& origin, Win32Window::Size& size) {
  POINT primary_point = {0, 0};
  HMONITOR monitor = MonitorFromPoint(primary_point, MONITOR_DEFAULTTOPRIMARY);

  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    // Fallback default
    origin = Win32Window::Point(10, 10);
    size = Win32Window::Size(1280, 720);
    return;
  }

  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = (dpi > 0) ? (dpi / 96.0) : 1.0;

  // Convert to logical work area dimensions (matching Win32Window::Create Scale).
  int work_w = static_cast<int>((monitor_info.rcWork.right - monitor_info.rcWork.left) / scale_factor);
  int work_h = static_cast<int>((monitor_info.rcWork.bottom - monitor_info.rcWork.top) / scale_factor);
  int work_left = static_cast<int>(monitor_info.rcWork.left / scale_factor);
  int work_top = static_cast<int>(monitor_info.rcWork.top / scale_factor);

  // Downscale by one tier maintaining 16:9 golden ratio.
  int target_w = 1280;
  int target_h = 720;

  if (work_w >= 1920 && work_h >= 1000) {
    // 2K/4K large screens: downscale to 1440x810 for comfortable margins.
    target_w = 1440;
    target_h = 810;
  } else if (work_w >= 1400 && work_h >= 800) {
    // Standard 1080P screens: downscale to 1280x720 (720P).
    target_w = 1280;
    target_h = 720;
  } else {
    // Laptops / smaller displays (e.g. 1366x768): scale down to 1024x576 to prevent taskbar cutoff.
    target_w = 1024;
    target_h = 576;
  }

  // Calculate centered coordinates inside the work area.
  int origin_x = work_left + (work_w - target_w) / 2;
  int origin_y = work_top + (work_h - target_h) / 2;

  origin = Win32Window::Point(static_cast<unsigned int>(std::max(0, origin_x)),
                              static_cast<unsigned int>(std::max(0, origin_y)));
  size = Win32Window::Size(static_cast<unsigned int>(target_w),
                           static_cast<unsigned int>(target_h));
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  // Explicitly disable Impeller to fall back to the Skia rendering backend on Windows.
  // Avoids external Direct3D 11 shared texture synchronization jitter with media_kit.
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  CalculateDefaultWindowBounds(origin, size);
  if (!window.Create(L"zakoway", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
