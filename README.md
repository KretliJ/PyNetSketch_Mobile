# PyNetSketch Mobile 📱

  PyNetSketch Mobile is the companion application for the PyNetSketch network analysis suite. Built with Flutter, it serves as a remote control and visualization frontend for PyNetSketch Probes running on a local network.

  This app allows users to perform network diagnostics from their mobile device by leveraging the raw socket power of a desktop/server probe, bypassing the OS restrictions typically found on Android and iOS (such as the inability to perform ARP scans or raw packet manipulation).

# 🌟 Key Features

  * UDP Auto-Discovery: Automatically finds PyNetSketch Probes running on the local network via UDP broadcast. No manual IP entry required.
  * Remote Control Dashboard: Send commands to the probe to execute:
    * Ping: Check host reachability.
    * Port Scan: identify open ports on a target.
    * Traceroute: Visual hop-by-hop path analysis.
    * Network Scan (ARP): Discover all devices on a subnet.

  * Real-Time Streaming: Results (traceroute hops, scan findings) appear instantly as they are discovered by the probe.
  * Log Viewer: Retrieve persistent logs from the probe directly on the phone.
  * Structured Visualization: Clean UI with icons, timers, and organized lists instead of raw console text.

# 🛠️ Architecture

  * PyNetSketch Mobile follows a Distributed Client-Server Architecture:
    * The Probe (Server): A PC or Raspberry Pi running the main PyNetSketch Python application in "Server Mode". It handles raw socket operations (Scapy/Rust).
    * The Mobile App (Client): A Flutter app that connects via TCP Sockets to the Probe. It sends JSON commands and renders JSON responses.

# 📦 Prerequisites

  * Flutter SDK: Install Flutter
  * Android Device/Emulator: Enable USB Debugging.
  * PyNetSketch Probe: You must have the desktop application running on the same local network in "Server Mode".

# 🚀 Getting Started

Start the Probe:
On your PC, run:
  ```
  python gui_app.py
  ```
Select "📡 Server (Remote Probe)" in the launcher.

Run the Mobile App:
Connect your phone via USB and run:
  ```
  cd pynetsketch_mobile
  flutter run
  ```

Connect:
The app will automatically scan for the probe. Tap the card when it appears to open the control dashboard.

📸 Screenshots

Auto Discovery

Dashboard & Results

(screenshot of discovery list)

(screenshot of scan results)

# ⚠️ Note on Permissions

This app requires internet permission to communicate with the local network. It does not require Root access on the phone, as all privileged network operations are offloaded to the Probe.

Part of the PyNetSketch Project.

# 🛠️ Installation for development

1. Install Flutter SDK
  * Download: Go to the official Flutter [Windows install page](https://docs.flutter.dev/get-started).
  * Extract: Download the zip file and extract it to a simple path like C:\src\flutter. Do not put it in Program Files.
  * Update Path:
    * Edit environment variables.
    * append the full path to flutter\bin (e.g., C:\src\flutter\bin).
      
2. Run Flutter Doctor

Open a new Command Prompt or PowerShell window and run:

```
flutter doctor
```

This command checks your environment and displays a report. It will tell you if you are missing the Android SDK or other tools.      

3. Install Android Studio & SDK
   
  * Download: Install [Android Studio](https://developer.android.com/studio).
  * Setup Wizard: Run the startup wizard. Iinstall latest Android SDK, Android SDK Command-line Tools, and Android SDK Build-Tools.
  * Licenses: Run flutter doctor --android-licenses in your terminal and accept all agreements by typing y.

4. Configure Android Device
  
  * Developer Mode: Go to Settings > About Phone. Tap Build Number 7 times until you see "You are now a developer!".
  * USB Debugging: Go to Settings > System > Developer Options. Enable USB Debugging.
  * Connect: Plug your phone into your PC via USB.
  * Verify: Run flutter devices in your terminal. You should see your phone listed.

5. Verify Setup with PyNetSketch
  
  * Navigate to your mobile project folder:
```
cd pynetsketch_mobile
```

  * Install dependencies:
```
flutter pub get
```

  * Run application:
```
flutter run
```
