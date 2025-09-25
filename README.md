#  RippleBeam
[RippleBeam Guide](https://confluence.sd.apple.com/display/AFD/RippleBeam)

📡 RippleBeam – macOS Diagnostic & Firmware Toolkit

RippleBeam is a macOS-based all-in-one firmware and diagnostics tool built for Apple internal use. It provides a powerful interface for engineering (EE), test (TE), and CM teams to interact with DUTs via serial ports, perform firmware updates, analyze logs, and automate Radar-based workflows.

⸻

🧩 Key Features

✅ Control Panel
	•	Run initialization flows like GN Init
	•	Automatically extract the KIS serial port
	•	Launch into Console or EB update with pre-filled paths

💻 Console (Serial Terminal)
	•	Multi-line command input with loop and delay controls
	•	Real-time command highlighting (iTerm-style: focused command is bold, others grayed out)
	•	Supports Macros (e.g. ##BIF, ##CIF, ##DELAY)
	•	Toggle between Raw and Hex display formats
	•	Fully scrollable, collapsible, and searchable log view

🔧 Firmware Update (EB Mode)
	•	Automatically retrieves ECID and injects it into Radar upload comments
	•	Supports uploading .ftab and associated files to Radar
	•	Auto-download .tgz from Radar, extract .uarp, rename and place in correct path
	•	Supports:
	•	Standard EB Restore
	•	Case-product simplified flashing (BLE / STM32 / R2 / All)
	•	Auto-fills --target= using ft version case

📊 Dashboard
	•	Parses the output of ft fw_info over the active Console serial port
	•	Displays FW version, build info, and metadata in a structured table

🤖 AI Log Summary
	•	Summarizes raw logs using custom LLM integration
	•	Handles 3 cases:
	1.	Unknown command → suggests alternatives using commands.json
	2.	Valid command failed → analyzes based on h90.json expectations and logs
	3.	Script or Python failure → general stack trace analysis
	•	Returns structured summary with test name, error cause, and suggested fix

📁 Regex-Based Plotting
	•	Extracts X/Y data from logs using user-defined regex
	•	Renders interactive line charts inside the app
	•	Supports CSV export for data visualization and debugging

⸻

📦 Installation
	1.	Clone or download the app from rdar://150989161
	2.	Before first launch, run the embedded python3.11.pkg installer (inside /Resources)
    If Python 3.11 is already installed on your machine, you may skip this step.
	3.	Launch the app and grant serial port permissions when prompted.

⸻

🛠 System Requirements
	•	macOS 13.0 or later (Ventura+)
	•	Python 3.11 (bundled)
	•	Internal Apple network access for Radar API and bundle sync features

⸻

💡 Usage Tips
	•	Start from the Control tab to initialize your device
	•	Use Console for direct interaction with DUT using serial commands
	•	Use Dashboard to inspect DUT version info at a glance
	•	Go to Firmware Update for EB flashing workflows (standard or case-mode)
	•	Use Log Summary button anytime to auto-analyze current logs
	•	Use Plot to visualize regex-extracted data (e.g. timestamps, voltage trends)
 
⸻

🧪 Development Notes
	•	Built using SwiftUI + Combine
	•	Serial I/O via custom SerialPort class (ORSSerial-based)
	•	AI summary powered by LLM + custom structured parser
	•	Radar integration uses Apple internal Radar API and Kerberos tokens
	•	Fully sandboxed with bookmarkData support for file persistence

⸻

🧑‍💻 Contributing

RippleBeam is designed for Apple internal engineers.
To propose changes, create a PR under the debug/* branch and ensure you test the following:

	•	Console command send/receive
	•	Firmware update flow (ftab → Radar → extract → restore)
	•	AI summary from logs
	•	Dashboard version detection
	•	Regex plotting and CSV export

    
## Project Structure

```bash
.
├── Assets.xcassets
│   ├── AccentColor.colorset
│   ├── ai.imageset
│   ├── AppIcon.appiconset
│   └── Contents.json
├── audiofactorydiagtools
│   ├── 3.11
│   ├── ai
│   ├── astris_script
│   ├── CaseEB
│   ├── config
│   ├── diagsterm
│   ├── doc
│   ├── download
│   ├── goldrestore_b747_EVT
│   ├── goldrestore_durant
│   ├── libusb-1.0.26
│   ├── Makefile
│   ├── personalize_fw
│   ├── README
│   ├── schema.json
│   ├── scripts
│   ├── Sentinel
│   ├── sequencer
│   ├── syscfg_migrate
│   ├── test_suites
│   ├── tools
│   └── utilities
├── bot.swift
├── CodeEditor.swift
├── Console.swift
├── ContentView.swift
├── Control.swift
├── CSV.swift
├── CustomViewClasses.swift
├── Dashboard.swift
├── Debug.swift
├── EB.swift
├── global.swift
├── Info.plist
├── Logging.swift
├── LogSummaryLauncher.swift
├── Plot.swift
├── Preview Content
│   └── Preview Assets.xcassets
├── PythonScriptRunner.swift
├── ripplebeam.entitlements
├── ripplebeam.xcodeproj
│   ├── project.pbxproj
│   ├── project.xcworkspace
│   └── xcuserdata
├── ripplebeamApp.swift
├── Schema.swift
├── scripts
│   └── search_radar.py
├── Search.swift
├── SerialPort.swift
├── Settings.swift
├── Terminal.swift
├── UnifiedAssistantLauncher.swift
└── Utils.swift