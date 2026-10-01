#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>

#include "win32_window.h"

// A window that hosts the Flutter view, a notification-area (tray) icon, and the
// method channel the Dart side uses to ask for tray and notification behaviour.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Channel backing `capsiPlatformChannel` in the Dart layer.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      platform_channel_;

  // Notification-area state.
  bool tray_visible_ = false;
  bool notifications_enabled_ = true;
  UINT tray_callback_message_ = 0;
  HICON tray_icon_ = nullptr;

  // Registers the platform channel and creates the tray icon.
  void SetUpPlatformChannel();
  void HandlePlatformCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Shell_NotifyIcon wrapper; |message| is NIM_ADD, NIM_DELETE or NIM_MODIFY.
  void UpdateTrayIcon();
  void DeleteTrayIcon();

  // Shows a tray balloon. Silently does nothing when notifications are off.
  void ShowNotification(const std::string& title, const std::string& body);

  // Menu command identifiers for the tray context menu.
  static constexpr UINT kTrayOpen = 1001;
  static constexpr UINT kTrayQuit = 1002;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
