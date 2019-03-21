# Vorgehen

## via GPIO/Shell Möglichkeit
    das Programm gpio.. .py  unter /Programs/control/ wird gestartet.
    das Argument startnow kann übergeben werden um direkt zu starten.
    das Arg. --help gibt Infos und startet das Programm.
    ohne Argumente wird erst nach drücken des GPIOs eine Aufnahme gestartet.
    nach weiterem drücken wird die Aufnahme beendet.
    
## via bluetooth_recorder_starter.sh
    zum Ordnungsgemäßen starten wird ./bluetooth_recorder_starter.sh
    aufgerufen.
    zum sauberen beenden wird dieser via SIGINT (== Ctrl +C) beendet. dadurch werden die
    Audio Files gezipped.
    das kann bspw. via htop KILL --> SIGINT (nr.2)
    geschehen.
    hierbei sollte der Prozess mit der kleinsten PID
    gewählt werden.

## via automatischer Start
    die service Datei save-audio..service muss in /etc/systemd/system kopiert werden. 
    nach einem daemon reload wird bei Verbindung mit dem ATM Messgerät wird eine Aufnahme 
    automatisch gestartet.
