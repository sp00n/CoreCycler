import os
import ctypes
from PyQt6.QtWidgets import QMessageBox

def launch_zentimings():
    # Define the path to ZenTimings.exe and its directory
    base_dir = os.getcwd()  # Use the current working directory (set to the .exe's directory)
    zentimings_dir = os.path.join(base_dir, "tools", "ZenTimings")
    zentimings_path = os.path.join(zentimings_dir, "ZenTimings.exe")

    # Check if ZenTimings.exe exists
    if not os.path.exists(zentimings_path):
        QMessageBox.critical(None, "Error", f"ZenTimings.exe not found at {zentimings_path}")
        return

    # Launch ZenTimings.exe with elevation using ShellExecuteW
    result = ctypes.windll.shell32.ShellExecuteW(
        None,           # No parent window (hwnd)
        "runas",        # Verb to request elevation
        zentimings_path, # Path to the executable
        None,           # No command-line parameters
        zentimings_dir,  # Working directory
        1               # SW_SHOWNORMAL to show the window
    )

    # Check the return value to handle success or failure
    if result <= 32:
        if result == 1223:  # ERROR_CANCELLED (user denied elevation)
            QMessageBox.warning(None, "Warning", "Elevation request was cancelled.")
        else:
            QMessageBox.critical(None, "Error", f"Failed to launch ZenTimings: ShellExecute returned {result}")
