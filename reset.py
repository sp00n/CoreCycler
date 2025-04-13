import os
import shutil
from PyQt6 import QtWidgets

def reset_config(ui, load_all_configs):
    reply = QtWidgets.QMessageBox.question(
        None,
        "Confirm Reset",
        "Are you sure you want to reset to default settings?",
        QtWidgets.QMessageBox.StandardButton.Yes | QtWidgets.QMessageBox.StandardButton.No,
        QtWidgets.QMessageBox.StandardButton.No
    )
    if reply == QtWidgets.QMessageBox.StandardButton.Yes:
        working_dir = os.getcwd()
        default_config_path = os.path.join(working_dir, 'configs', 'default.config.ini')
        config_path = os.path.join(working_dir, 'config.ini')
        
        if not os.path.exists(default_config_path):
            QtWidgets.QMessageBox.warning(
                None,
                "Warning",
                f"Default config file not found at {default_config_path}."
            )
            return
        
        try:
            shutil.copyfile(default_config_path, config_path)
            load_all_configs(ui)  # Refresh the GUI with default settings
            ui.general_useConfigFile_lineEdit.clear()  # Explicitly clear the config file name
        except Exception as e:
            QtWidgets.QMessageBox.critical(
                None,
                "Error",
                f"Failed to reset config: {e}"
            )
