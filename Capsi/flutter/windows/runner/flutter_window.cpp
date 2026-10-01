#include "flutter_window.h"

#include <optional>
#include <string>

#include <windows.h>
#include <shellapi.h>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {

// Convert UTF-8 to UTF-16 for the Win32 wide APIs.
//
// The Dart side sends UTF-8 strings over the method channel, and every Win32
// call here is the W variant, so the conversion has to happen exactly once. A
// string that cannot be converted yields an empty buffer rather than throwing:
// the notification is cosmetic, and a mangled body must never crash the app.
std::wstring ToWide(const std::string& value) {
  if (value.empty()) {
    return std::wstring();
  }
  const int needed = ::MultiByteToWideChar(CP_UTF8, 0, value.data(),
                                          static_cast<int>(value.size()),
                                          nullptr, 0);
  if (needed <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(needed), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, value.data(),
                        static_cast<int>(value.size()), wide.data(), needed);
  return wide;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {
  // A private window message for the tray icon's clicks. Registered at runtime
  // so the value cannot collide with a system message; the value only has to be
  // stable for the lifetime of this process.
  tray_callback_message_ = RegisterWindowMessageW(L"win.capsi.app/TrayCallback");
}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  SetUpPlatformChannel();
  UpdateTrayIcon();

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  DeleteTrayIcon();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

// Wires `capsiPlatformChannel` in the Dart layer to the Windows host. The name
// must match the MethodChannel constant in lib/main.dart exactly.
void FlutterWindow::SetUpPlatformChannel() {
  platform_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "win.capsi.app/platform",
          &flutter::StandardMethodCodec::GetInstance());

  platform_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        HandlePlatformCall(call, std::move(result));
      });
}

void FlutterWindow::HandlePlatformCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  // `method_name()` hands back a std::string, so it is compared as one rather
  // than being squeezed through strcmp.
  const std::string& name = call.method_name();

  if (name == "notify") {
    const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
    std::string title = "Capsi";
    std::string body;
    if (arguments != nullptr) {
      auto title_it = arguments->find(flutter::EncodableValue("title"));
      if (title_it != arguments->end()) {
        if (const auto* value = std::get_if<std::string>(&title_it->second)) {
          title = *value;
        }
      }
      auto body_it = arguments->find(flutter::EncodableValue("body"));
      if (body_it != arguments->end()) {
        if (const auto* value = std::get_if<std::string>(&body_it->second)) {
          body = *value;
        }
      }
    }
    ShowNotification(title, body);
    result->Success(flutter::EncodableValue(true));
    return;
  }

  if (name == "setNotificationsEnabled") {
    // Windows has no separate runtime notification permission, so the only
    // thing to honour is the preference the user set in the app.
    const auto* enabled = std::get_if<bool>(call.arguments());
    notifications_enabled_ = enabled != nullptr ? *enabled : true;
    result->Success();
    return;
  }

  result->NotImplemented();
}

void FlutterWindow::UpdateTrayIcon() {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = GetHandle();
  data.uID = 1;

  if (!tray_visible_) {
    // The application icon is already part of the executable, so the tray entry
    // reuses it instead of shipping a second copy of the artwork.
    tray_icon_ = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
    if (tray_icon_ == nullptr) {
      return;
    }
    data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    data.hIcon = tray_icon_;
    data.uCallbackMessage = tray_callback_message_;
    wcscpy_s(data.szTip, L"Capsi");
    if (Shell_NotifyIconW(NIM_ADD, &data)) {
      tray_visible_ = true;
    }
    return;
  }

  Shell_NotifyIconW(NIM_MODIFY, &data);
}

void FlutterWindow::DeleteTrayIcon() {
  if (!tray_visible_) {
    return;
  }
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = GetHandle();
  data.uID = 1;
  Shell_NotifyIconW(NIM_DELETE, &data);
  tray_visible_ = false;
}

void FlutterWindow::ShowNotification(const std::string& title,
                                     const std::string& body) {
  if (!notifications_enabled_ || !tray_visible_) {
    // A balloon can only be attached to a tray icon, so notifications imply
    // the tray is present. The Dart layer skips the call while the window is in
    // the foreground, which is the other case where this would be noise.
    return;
  }

  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(NOTIFYICONDATAW);
  data.hWnd = GetHandle();
  data.uID = 1;
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO;
  // The balloon title and body are fixed-size fields in NOTIFYICONDATAW
  // (64 and 256 wide characters). The sizes are spelled out and the copies are
  // truncated, so a long device name can never overrun the buffer.
  constexpr size_t kInfoTitleChars = 64;
  constexpr size_t kInfoChars = 256;
  const std::wstring wide_title = ToWide(title);
  const std::wstring wide_body = ToWide(body);
  wcsncpy_s(data.szInfoTitle, kInfoTitleChars, wide_title.c_str(), _TRUNCATE);
  wcsncpy_s(data.szInfo, kInfoChars, wide_body.c_str(), _TRUNCATE);
  // Clicking the balloon should bring the window back, which only works if the
  // taskbar button exists.
  data.dwInfoFlags |= NIIF_USER;
  Shell_NotifyIconW(NIM_MODIFY, &data);
  ShowWindow(GetHandle(), SW_SHOW);
  SetForegroundWindow(GetHandle());
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  // Tray icon clicks arrive as the private message registered in the constructor.
  if (tray_callback_message_ != 0 && message == tray_callback_message_) {
    const auto event = LOWORD(lparam);
    if (event == WM_LBUTTONDBLCLK || event == WM_LBUTTONUP) {
      Show();
      SetForegroundWindow(GetHandle());
      return 0;
    }
    if (event == WM_CONTEXTMENU || event == WM_RBUTTONUP) {
      // A menu is what gives the tray entry a way to quit; without it the icon
      // would only ever be able to bring the window forward.
      const HMENU menu = CreatePopupMenu();
      AppendMenuW(menu, MF_STRING, kTrayOpen, L"Open Capsi");
      AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
      AppendMenuW(menu, MF_STRING, kTrayQuit, L"Quit Capsi");
      POINT cursor{};
      GetCursorPos(&cursor);
      // Required so the menu dismisses when the user clicks elsewhere.
      SetForegroundWindow(GetHandle());
      const UINT choice = static_cast<UINT>(TrackPopupMenu(
          menu, TPM_RIGHTBUTTON, cursor.x, cursor.y, 0, GetHandle(), nullptr));
      DestroyMenu(menu);
      if (choice == kTrayQuit) {
        DestroyWindow(GetHandle());
      } else if (choice == kTrayOpen) {
        Show();
        SetForegroundWindow(GetHandle());
      }
      return 0;
    }
    return 0;
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
