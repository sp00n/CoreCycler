import configparser

def load_prime95_custom_config(ui):
    """
    Load settings from the [Prime95Custom] section of config.ini into the GUI.
    
    Args:
        ui: The GUI object containing the widgets to be updated.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Check if the [Prime95Custom] section exists
    if 'Prime95Custom' in config:
        section = config['Prime95Custom']
        
        # Determine which radio button to check based on the config values
        cpu_supports_avx = section.get('cpuSupportsAvx', '0') == '1'
        cpu_supports_avx2 = section.get('cpuSupportsAvx2', '0') == '1'
        cpu_supports_fma3 = section.get('cpuSupportsFma3', '0') == '1'
        cpu_supports_avx512 = section.get('cpuSupportsAvx512', '0') == '1'

        if cpu_supports_avx512:
            ui.prime95Custom_cpuSupportsAvx512_radioButton.setChecked(True)
        elif cpu_supports_fma3:
            ui.prime95Custom_cpuSupportsFma3_radioButton.setChecked(True)
        elif cpu_supports_avx2:
            ui.prime95Custom_cpuSupportsAvx2_radioButton.setChecked(True)
        elif cpu_supports_avx:
            ui.pirme95Custom_cpuSupportsAvx_radioButton.setChecked(True)
        else:
            ui.prime95Custom_cpuSupportsSse_radioButton.setChecked(True)
        
        # Load line edit texts with defaults
        ui.prime95Custom_minTortureFft_lineEdit.setText(section.get('minTortureFft', '4'))
        ui.prime95Custom_maxTortureFft_lineEdit.setText(section.get('maxTortureFft', '1344'))
        ui.prime95Custom_tortureMem_lineEdit.setText(section.get('tortureMem', '0'))
        
        # Load spinbox value, converting string to int with error handling
        try:
            torture_time = int(section.get('tortureTime', '1'))
        except ValueError:
            torture_time = 1  # Default to 1 if conversion fails
        ui.prime95Custom_tortureTime_spinBox.setValue(torture_time)
    else:
        # If section is missing, set default values in the GUI (SSE as default)
        ui.prime95Custom_cpuSupportsSse_radioButton.setChecked(True)
        ui.pirme95Custom_cpuSupportsAvx_radioButton.setChecked(False)
        ui.prime95Custom_cpuSupportsAvx2_radioButton.setChecked(False)
        ui.prime95Custom_cpuSupportsFma3_radioButton.setChecked(False)
        ui.prime95Custom_cpuSupportsAvx512_radioButton.setChecked(False)
        ui.prime95Custom_minTortureFft_lineEdit.setText('4')
        ui.prime95Custom_maxTortureFft_lineEdit.setText('1344')
        ui.prime95Custom_tortureMem_lineEdit.setText('0')
        ui.prime95Custom_tortureTime_spinBox.setValue(1)

def apply_prime95_custom_config(ui):
    """
    Apply current GUI settings to the [Prime95Custom] section of config.ini.
    
    Args:
        ui: The GUI object containing the widgets with current values.
    """
    config = configparser.ConfigParser()
    config.read('config.ini')
    
    # Ensure the [Prime95Custom] section exists
    if 'Prime95Custom' not in config:
        config['Prime95Custom'] = {}
    
    section = config['Prime95Custom']
    
    # Set CPU support settings based on the selected radio button
    if ui.prime95Custom_cpuSupportsSse_radioButton.isChecked():
        section['cpuSupportsAvx'] = '0'
        section['cpuSupportsAvx2'] = '0'
        section['cpuSupportsFma3'] = '0'
        section['cpuSupportsAvx512'] = '0'
    elif ui.pirme95Custom_cpuSupportsAvx_radioButton.isChecked():
        section['cpuSupportsAvx'] = '1'
        section['cpuSupportsAvx2'] = '0'
        section['cpuSupportsFma3'] = '0'
        section['cpuSupportsAvx512'] = '0'
    elif ui.prime95Custom_cpuSupportsAvx2_radioButton.isChecked():
        section['cpuSupportsAvx'] = '1'
        section['cpuSupportsAvx2'] = '1'
        section['cpuSupportsFma3'] = '0'
        section['cpuSupportsAvx512'] = '0'
    elif ui.prime95Custom_cpuSupportsFma3_radioButton.isChecked():
        section['cpuSupportsAvx'] = '1'
        section['cpuSupportsAvx2'] = '1'
        section['cpuSupportsFma3'] = '1'
        section['cpuSupportsAvx512'] = '0'
    elif ui.prime95Custom_cpuSupportsAvx512_radioButton.isChecked():
        section['cpuSupportsAvx'] = '1'
        section['cpuSupportsAvx2'] = '1'
        section['cpuSupportsFma3'] = '1'
        section['cpuSupportsAvx512'] = '1'
    
    # Save line edit texts directly
    section['minTortureFft'] = ui.prime95Custom_minTortureFft_lineEdit.text()
    section['maxTortureFft'] = ui.prime95Custom_maxTortureFft_lineEdit.text()
    section['tortureMem'] = ui.prime95Custom_tortureMem_lineEdit.text()
    
    # Save spinbox value as a string
    section['tortureTime'] = str(ui.prime95Custom_tortureTime_spinBox.value())
    
    # Write the updated config to file
    with open('config.ini', 'w') as configfile:
        config.write(configfile)
