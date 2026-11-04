#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <string>

#include "flutter_window.h"
#include "utils.h"

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

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  std::wstring title = L"frontend";
  // The 5-person chat test relaunches this exe with --test-slot=N (0-4):
  // lay the windows side by side so every tester is visible at once.
  for (const auto& arg : command_line_arguments) {
    if (arg.rfind("--test-slot=", 0) != 0) continue;
    const int slot = std::clamp(std::atoi(arg.c_str() + 12), 0, 4);
    RECT work;
    ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work, 0);
    // Win32Window scales by DPI, so work in logical pixels.
    const double scale = ::GetDpiForSystem() / 96.0;
    const int total = static_cast<int>((work.right - work.left) / scale);
    const int height = static_cast<int>((work.bottom - work.top) / scale);
    // Below ~380px the phone layout gets cramped; overlap instead.
    const int width = std::max(380, total / 5);
    const int step = std::max(0, (total - width) / 4);
    origin = Win32Window::Point(
        static_cast<unsigned int>(work.left / scale + slot * step),
        static_cast<unsigned int>(work.top / scale));
    size = Win32Window::Size(width, height);
    title = L"BC Test " + std::to_wstring(slot + 1);
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (!window.Create(title, origin, size)) {
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
