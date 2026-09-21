MASTER PROMPT — CAPSI by CAPSICOM
Build Capsi, a lightweight local-network communication application by CAPSICOM.
The attached image is the official Capsi logo. Treat this logo as the primary source of truth for the visual identity. Do not redesign, replace, distort, or reinterpret the logo. Build the entire application's visual language around it.
1. Product identity
Brand: Capsi
Company: CAPSICOM
Product naming: Capsi by CAPSICOM
Capsi is a deliberately simple, lightweight desktop communication utility that allows computers on the same local network to communicate without requiring the internet, cloud accounts, external servers, or complicated configuration.
Core philosophy:
Download. Run. Connect.
Capsi should feel less like a large traditional messaging application and more like a small, useful system utility that happens to have a beautiful graphical interface.
The application should be:
lightweight
fast
quiet
local-first
offline-first
simple
practical
reliable
modern
unobtrusive
easy to understand
usable without technical knowledge
Do NOT turn Capsi into a WhatsApp clone.
Do NOT add unnecessary social-media features.
Do NOT create a bloated SaaS-style dashboard.
Do NOT introduce accounts, cloud synchronization, online registration, or unnecessary onboarding.
2. Core user experience
The intended experience is:
Download Capsi
      ↓
Run Capsi.exe
      ↓
Capsi logo splash screen
      ↓
First launch initializes the device
      ↓
Automatically discover Capsi devices
      ↓
Capsi GUI opens
      ↓
User is immediately on the local network
There should be essentially zero technical configuration for a normal user.
The user should not have to enter:
IP addresses
ports
server addresses
usernames
cloud credentials
API keys
network configuration
Capsi should automatically discover compatible Capsi devices on the local network.
3. First-launch experience
When Capsi.exe is launched for the first time, display a minimal branded splash screen.
Use the uploaded Capsi logo prominently.
The splash screen should feel premium but extremely simple.
Example:
                 [CAPSI LOGO]


                    Capsi

              by CAPSICOM


          Finding Capsi devices...
Do not overcrowd the splash screen.
Use subtle animation only.
Possible animation:
logo gently fades in
logo slightly scales into position
small connection indicator appears
application transitions smoothly into the main interface
The splash screen should disappear automatically.
Do not create a long loading animation.
Capsi should feel fast.
4. First-time device setup
On first launch, after the splash screen, ask only for the local device name.
Example:
┌─────────────────────────────────────┐
│                                     │
│          Welcome to Capsi           │
│                                     │
│   What should other devices see?    │
│                                     │
│   ┌─────────────────────────────┐   │
│   │ Office-PC                   │   │
│   └─────────────────────────────┘   │
│                                     │
│             [ Continue ]             │
│                                     │
└─────────────────────────────────────┘
Keep this extremely simple.
Store the device identity locally.
After this, never force the user through the setup again unless they explicitly reset their identity/settings.
5. Main GUI
Create a desktop interface that feels like a modern utility, not a web application.
Suggested structure:
┌───────────────────────────────────────────────────────┐
│  [Capsi Logo] Capsi                         — □ ×     │
├───────────────────────────────────────────────────────┤
│                                                       │
│  DEVICES                         CONVERSATION         │
│  ─────────────                  ─────────────────     │
│                                                       │
│  🟢 Office-PC                   Select a device       │
│  🟢 Reception                                         │
│  🟢 Manager-PC                  Start a conversation  │
│  🟢 Accounts                                           │
│  🟢 Store-PC                                           │
│                                                       │
│                                                       │
│                                                       │
├───────────────────────────────────────────────────────┤
│  🟢 Connected to local network              Capsi     │
└───────────────────────────────────────────────────────┘
The interface should work beautifully at approximately:
900×600
1024×768
1280×720
1366×768
1920×1080
It should remain usable when resized.
6. Visual identity
Study the attached Capsi logo carefully.
Extract the visual language from it.
The logo contains a distinctive:
light/white central form
green stem/accent
dark/black background
organic rounded shapes
strong dark outline
playful but controlled character
Use those characteristics as inspiration for the interface.
Do not literally fill the application with pepper graphics.
The logo is the identity.
The UI should inherit its:
curves
proportions
contrast
accent color
visual softness
personality
The UI should feel like the software version of the logo.
Color system
Sample the actual colors from the supplied logo rather than inventing unrelated brand colors.
Build a design-token system:
:root {
    --capsi-bg: ...;
    --capsi-surface: ...;
    --capsi-surface-2: ...;
    --capsi-text: ...;
    --capsi-muted: ...;
    --capsi-accent: ...;
    --capsi-border: ...;
    --capsi-online: ...;
}
The green from the logo should become the primary brand accent.
The dark background should influence the primary dark theme.
Use the light color from the logo for primary text and surfaces where appropriate.
Do not use excessive gradients.
Do not use generic “AI purple/blue” colors.
Do not make it look like Discord, Slack, Teams, Telegram, or WhatsApp.
7. Design language
Capsi should have:
rounded but restrained corners
clean typography
generous spacing
subtle borders
subtle shadows
minimal icons
smooth hover states
compact controls
clear hierarchy
strong whitespace
Avoid:
excessive glassmorphism
giant cards
excessive gradients
unnecessary animations
excessive rounded pills
dashboard clutter
oversized typography
neon colors
generic SaaS aesthetics
The interface should communicate:
Small. Quiet. Useful.
8. Device discovery
Capsi devices should automatically discover each other over the local network.
Conceptually:
             LOCAL NETWORK

        ┌───────────────────┐
        │   Wi-Fi / LAN     │
        └─────────┬─────────┘
                  │
       ┌──────────┼──────────┐
       │          │          │
   Office-PC  Manager-PC  Reception
      Capsi       Capsi       Capsi
No internet should be required for local messaging.
Use appropriate local-network discovery mechanisms.
Separate:
Discovery
Messaging
File Transfer
Identity
Persistence
UI
into independent modules.
9. Messaging
V1 should support:
Private messages
Office-PC

┌──────────────────────────────────┐
│                                  │
│ Reception:                       │
│ Customer is waiting.             │
│                                  │
│                       You:       │
│                       Coming.    │
│                                  │
├──────────────────────────────────┤
│ Type a message...          [→]   │
└──────────────────────────────────┘
Support:
text messages
timestamps
delivery state
online/offline presence
local message history
unread indicators
Keep the message system simple.
10. Groups
Allow users to create simple local groups:
GROUPS

General
Management
Sales
Reception
Accounts
Groups should remain local to the Capsi network.
11. Broadcast
One of Capsi's useful features should be Send to Everyone.
Example:
┌──────────────────────────────┐
│ Send to everyone             │
│                              │
│ Internet is currently down.  │
│                              │
│              [ Send ]        │
└──────────────────────────────┘
This is particularly useful for offices, schools, workshops, hotels, warehouses, etc.
12. File transfer
Add file transfer without turning Capsi into a cloud-storage application.
Users should be able to:
drag a file into a conversation
click Attach
send a file directly to another Capsi device
see transfer progress
accept/reject incoming files
Transfers should occur directly over the local network.
No cloud storage.
13. System tray
Capsi should be able to run quietly in the Windows system tray.
Example:
Capsi
  │
  ├── Open Capsi
  ├── Send message
  ├── Devices
  └── Quit
When the main window is closed, allow Capsi to remain running in the tray if appropriate.
Use the official Capsi logo/icon for the tray identity.
Tauri supports native system-tray functionality, so use the native layer rather than trying to fake this in HTML. �
Tauri
14. Architecture
Use:
Frontend
HTML
CSS
Vanilla JavaScript
Do not introduce React, Vue, Angular, Tailwind, Bootstrap, or another UI framework unless there is a compelling technical reason.
The interface should be understandable from the source code.
Desktop shell
Use Tauri.
Tauri is specifically designed for small desktop applications using web technologies for the frontend and a native backend where necessary. �
Tauri +1
Native layer
Use Rust for functionality that requires native operating-system/network capabilities.
Potential modules:
src-tauri/

network/
    discovery
    messaging
    file_transfer

identity/
    device_identity
    pairing

storage/
    settings
    messages

system/
    notifications
    tray

commands/
    discover
    send_message
    send_file
Expose only the required native functionality to the JavaScript frontend.
Tauri supports JavaScript-to-native commands through its IPC/command system. �
Tauri +1
15. Local storage
Capsi should store its own local information.
Use a lightweight local database such as SQLite where structured persistent data is required.
Store things such as:
Device identity
Device name
Known devices
Conversations
Messages
Groups
Settings
Transfer history
Never require a remote database.
16. Security
LAN does NOT automatically mean secure.
Design the system so that devices have cryptographic identities and communications can be authenticated and encrypted.
Use established cryptographic libraries and protocols.
Do not invent cryptography.
For first contact between two devices, consider a simple trust/pairing mechanism.
Example:
New Capsi device detected

"Manager-PC"

[ Accept ]     [ Ignore ]
Once trusted, the device should be recognized automatically.
17. Offline-first principle
The application must continue functioning when:
Internet = OFF
If:
Wi-Fi/LAN = ON
Internet = OFF
Capsi should continue to work normally.
The internet should not be part of the core messaging architecture.
18. Command-line mode
Capsi should also have a lightweight CLI interface.
The same executable should conceptually support:
Capsi.exe
→ launch GUI
and:
Capsi.exe peers
→ list discovered Capsi devices
and:
Capsi.exe send "Office-PC" "Meeting starts in 10 minutes"
→ send a message
and:
Capsi.exe send-all "Internet connection is currently unavailable"
→ broadcast a message
The CLI should be optional and should never interfere with the graphical experience.
This is important to the identity of Capsi:
Capsi is a utility first, application second.
19. Performance
Optimize for:
fast startup
low RAM usage
low CPU usage while idle
minimal background activity
small installation footprint
fast device discovery
fast message delivery
Capsi should feel almost instantaneous.
Avoid unnecessary background services.
Avoid polling aggressively.
Prefer event-driven networking.
Tauri's use of the operating system's native web renderer is intended to keep applications smaller than approaches that bundle a full browser runtime. �
Tauri +1
20. Window behavior
Make the main window feel like a polished native Windows application.
Consider:
custom title bar
Capsi logo
native window controls
subtle rounded corners where appropriate
dark theme
optional light theme
tray support
proper Windows notifications
keyboard shortcuts
accessible focus states
Do not make it look like a website trapped inside a window.
21. Branding
Use:
Capsi
for the product.
Use:
CAPSICOM
for the company attribution.
Do not write:
CAPSI
everywhere.
The intended brand styling is:
Capsi
with:
by CAPSICOM
used subtly in appropriate places.
For example:
Capsi

by CAPSICOM
on the splash screen.
The main application can simply say:
Capsi
22. Logo rules
The supplied logo is authoritative.
Use it for:
splash screen
application icon
system tray icon
about screen
installer/application branding
Do not:
redraw it
alter its proportions
change its colors
rotate it
add effects that obscure it
place it inside unnecessary containers
Create appropriate icon assets from the original logo while preserving its identity.
23. UX philosophy
Every feature must answer:
Does this make local communication easier?
If not, don't add it.
Capsi V1 should NOT contain:
social feeds
public profiles
cloud backups
advertisements
stories
reactions everywhere
public channels
social-media features
unnecessary analytics
AI assistant
cryptocurrency
subscriptions inside the application
complicated account management
Keep it boring.
Make it powerful.
24. Final product feeling
When somebody sees Capsi for the first time, the reaction should be:
“That's it?”
Then:
“Wait... it already found the other computers?”
And then:
“I can just send the message?”
That simplicity is the product.
25. Development requirements
Build the project as a real working application, not a static mockup.
Start with:
Phase 1
Capsi.exe
↓
Splash
↓
Device setup
↓
Main GUI
↓
LAN discovery
↓
Device list
Phase 2
Private messaging
Message history
Presence
Notifications
Phase 3
File transfer
Groups
Broadcast
Phase 4
CLI
Pairing/security
Tray
Backup/export
Keep the code modular so additional platforms can be added later.
Do not over-engineer V1.
26. Deliverables
Produce:
Capsi/
│
├── frontend/
│   ├── index.html
│   ├── styles.css
│   ├── app.js
│   ├── components/
│   └── assets/
│
├── src-tauri/
│   ├── src/
│   ├── Cargo.toml
│   └── tauri.conf.json
│
├── icons/
│   └── Capsi logo assets
│
├── README.md
└── package.json
The final application must build into a Windows executable/installer.
Tauri supports Windows application distribution through .msi and setup .exe packages. �
Tauri
MOST IMPORTANT DESIGN RULE
Do not make Capsi look like a generic software template.
The uploaded logo must drive the identity.
The final result should feel like:
A tiny piece of software with its own personality.
Not:
“A web dashboard wrapped in an EXE.”
The visual identity should communicate:
Capsi by CAPSICOM
Download. Run. Connect.
No cloud. No account. No unnecessary setup. Just local communication.
