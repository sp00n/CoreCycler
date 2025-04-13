import os
import subprocess
import ctypes

def launch_boost_tester():
    """Launch BoostTester.sp00n.exe from the tools folder."""
    try:
        os.startfile(os.path.join('tools', 'BoostTester.sp00n.exe'))
    except Exception as e:
        print(f"Error launching BoostTester: {e}")

def launch_pbo2_tuner():
    """Launch PBO2Tuner.exe from the PBO2Tuner folder within tools."""
    try:
        os.startfile(os.path.join('tools', 'PBO2Tuner', 'PBO2Tuner.exe'))
    except Exception as e:
        print(f"Error launching PBO2Tuner: {e}")

def launch_intel_voltage_control():
    """Launch IntelVoltageControl.exe from the IntelVoltageControl folder within tools."""
    try:
        os.startfile(os.path.join('tools', 'IntelVoltageControl', 'IntelVoltageControl.exe'))
    except Exception as e:
        print(f"Error launching IntelVoltageControl: {e}")

def launch_apic_ids():
    """Launch APICID.exe from the tools folder in a new terminal window without blocking the GUI."""
    try:
        apicid_exe_path = os.path.abspath(os.path.join('tools', 'APICID.exe'))
        if not os.path.exists(apicid_exe_path):
            QtWidgets.QMessageBox.critical(None, "Error", f"APICID.exe not found at: {apicid_exe_path}")
            return
        
        subprocess.Popen(['cmd.exe', '/k', f'.\\APICID.exe'],
                         cwd=os.path.dirname(apicid_exe_path),
                         creationflags=subprocess.CREATE_NEW_CONSOLE)
        
    except Exception as e:
        QtWidgets.QMessageBox.critical(None, "Error", f"Failed to launch APICID.exe: {e}")

def launch_core_tuner_x():
    """Launch CoreTunerX.exe from the tools folder."""
    try:
        os.startfile(os.path.join('tools', 'CoreTunerX.exe'))
    except Exception as e:
        print(f"Error launching CoreTunerX: {e}")

import os
import ctypes
import subprocess

def launch_enable_performance_counters():
    """Launch enable_performance_counter.bat from the tools folder with administrator privileges."""
    try:
        bat_path = os.path.abspath(os.path.join("tools", "enable_performance_counter.bat"))
        
        # Verify the batch file exists
        if not os.path.exists(bat_path):
            print(f"Batch file not found at: {bat_path}")
            return
        
        # Attempt to run with ShellExecuteW (preferred method for elevation)
        result = ctypes.windll.shell32.ShellExecuteW(None, "runas", "cmd.exe", f'/c "{bat_path}"', None, 1)
        if result <= 32:  # ShellExecuteW returns > 32 on success
            print(f"ShellExecuteW failed with code {result}. Possible UAC denial or insufficient permissions.")
        
    except AttributeError:
        # Fallback for non-Windows systems or if ctypes fails
        print("ShellExecuteW not available, attempting subprocess fallback...")
        try:
            subprocess.run([bat_path], shell=True, check=True, creationflags=subprocess.CREATE_NEW_CONSOLE)
        except subprocess.CalledProcessError as e:
            print(f"Subprocess failed with return code {e.returncode}")
        except Exception as e:
            print(f"Fallback error: {e}")
    except Exception as e:
        print(f"Error launching enable_performance_counter.bat: {e}")

def open_helpers_folder():
    """Open the helpers folder in the file explorer."""
    try:
        os.startfile('helpers')
    except Exception as e:
        print(f"Error opening helpers folder: {e}")
