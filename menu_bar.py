import os

def launch_readme():
    """Open readme.txt from the base directory."""
    try:
        os.startfile('readme.txt')
    except Exception as e:
        print(f"Error opening readme.txt: {e}")

def launch_license():
    """Open LICENSE from the base directory."""
    try:
        os.startfile('LICENSE')
    except Exception as e:
        print(f"Error opening LICENSE: {e}")

def setup_menu_connections(ui):
    """Connect menu actions to their respective functions."""
    ui.actionReadME_2.triggered.connect(launch_readme)
    ui.actionLicense_2.triggered.connect(launch_license)
