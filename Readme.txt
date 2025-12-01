# Visual C++ Redistributable Runtimes — All-in-One Installer

This repository contains a batch installer that runs Microsoft Visual C++ Redistributable packages (x86 and x64) silently or passively. It is intended to be run from a local folder that contains the redistributable EXE files.

Author GitHub account
- GitHub username embedded in the installer: GDJ2001

Important security note
- The script requests elevation (UAC) to install redistributables — it does not bypass UAC.
- If automatic elevation is blocked on your system (corporate AV/AppLocker/GPO), run the script by right-click → "Run as administrator", or use an elevated terminal.
- For large-scale/enterprise deployment without UAC prompts, use management tools such as SCCM, Intune, or scheduled tasks run as SYSTEM.

Files
- install_all_in_one_with_git.bat — Self-elevating (one attempt) installer with logging and optional Git metadata.
- install_log.txt — created at runtime, contains per-installer exit codes and a summary.
- README.md — this file.

How to use
1. Place this batch file in the same folder as the redistributable EXEs (examples in the script).
2. Verify the filenames and silent arguments inside the script match the EXE filenames you have. Common silent args:
   - /q or /quiet  (older/newer redistributables)
   - /passive /norestart
   - /norestart prevents automatic reboot
3. Run the script:
   - Double-click the batch — it will attempt one automatic elevation (UAC).  
   - If automatic elevation is blocked, right-click the batch and choose "Run as administrator".
   - Alternatively, run from an elevated terminal:
     - Open "Command Prompt (Admin)", change directory to the folder and run:
       install_all_in_one_with_git.bat
4. After the run, open install_log.txt to review exit codes and summary.

Optional: Commit to Git (manual / safe)
- The script includes an optional Git helper block that is disabled by default.
- If this folder is a git repository and you want the script to create a local commit:
  - The script embeds the GitHub username (GDJ2001).
  - Edit the batch and uncomment the git commands under "Optional Git helper".
  - Note: pushing to a remote requires credentials and is not automated by this script.