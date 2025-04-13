import subprocess
import os
import sys
from PyQt6.QtWidgets import QApplication, QMainWindow, QMessageBox
from mainwindow import Ui_MainWindow

def run_corecycler(main_window):
    exe_dir = os.path.dirname(sys.executable) if getattr(sys, 'frozen', False) else os.getcwd()
    subprocess.Popen('Run CoreCycler.bat', cwd=exe_dir)

if __name__ == "__main__":
    # Initialize the PyQt6 application
    app = QApplication(sys.argv)
    
    # Create the main window
    MainWindow = QMainWindow()
    
    # Set up the UI from mainwindow.py
    ui = Ui_MainWindow()
    ui.setupUi(MainWindow)
    
    # Connect the start_test_pushButton's clicked signal to the run_corecycler function
    ui.start_test_pushButton.clicked.connect(lambda: run_corecycler(MainWindow))
    
    # Show the main window
    MainWindow.show()
    
    # Run the application event loop
    sys.exit(app.exec())
