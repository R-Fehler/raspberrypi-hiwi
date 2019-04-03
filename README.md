# Repo für das ATM Torus Messgerät

weitere Dokumentation von Richard Fehler befindet sich unter [`./docs`](./docs).

## Installation des mitgelieferten Images (f. Raspi2)

die allgemeine Installation und Anwendung wird in  erläutert. [`./docs/Abschlussbericht_AnhangA.pdf`](./docs/Abschlussbericht_AnhangA.pdf)
Dabei wird das zu flashende Image mit beispielsweise [Balena Etcher](https://www.balena.io/etcher/) analog zum üblichen Vorgang mit Raspbian auf eine SD Karte die im FAT32  Format formatiert sein muss aufgespielt.

### Unter Linux vor dem ersten Booten

Dabei muss anschließend sichergestellt werden, dass kein Installer auf der SD Karte vorhanden ist.
Dieser ist unter `etc/profile.d/install.sh` zu finden, diese Dateien etfernen(SD Karte in Linux mounten).

Anschließend den git repo folder unter `pi/home/git/raspberry` selbst anlegen. 
Die Line Endings der Files anpassen mit [dos2unix](https://linux.die.net/man/1/dos2unix). (Da das zip unter Windows erstellt wurde).
Folgende Befehle in der Shell dabei ausführen: 

```bash
find . -type f -print0 | xargs -0 dos2unix
```

oder Multithreaded

```bash
find . -type f -print0 | xargs -0 -n 1 -P 4 dos2unix 
```

unter `./systemfiles/interfaces` bei Bedarf die Datei auf das Netzwerk anpassen oder entfernen(für DHCP).
eine gute Möglichkeit bietet der Terminal Network Manager `wicd-curses` nach dem ersten booten. Damit können wie in modernen OS einfach mehrere Netzwerke eingestellt werden. (überschreibt die `/etc/network/interface ` Einstellungen)
diese werden dann nach der Installation durch `wicd-curses` überschrieben.

## Git Repo Inhalt

## `./systemfiles/`

Hier sind system services und configs die durch `./install.sh` eingerichtet werden.
zu finden danach unter `/etc/network/` &
`/etc/systemd/system` 
& ... 

Wenn das automatische BT-Audio aufnehmen nicht gewollt ist 
kann vor dem ersten Booten/installieren die Datei 
`./systemfiles/save-bt-audio.service` entfernt werden.
Alternativ nach dem ersten Booten unter `/etc/systemd/` den Service entfernen.

## `./Programs/`

Hier befinden sich die Programme die zur Aufnahme von Daten ausgeführt werden.
das manuelle Aufnehmen von BT-Audio Daten wird durch **`./Programs/control/gpio-event-load-bt-audio.py`** gesteuert.

    arguments for : ./gpio-event-load-bt-audio.py
    startnow: startet Aufnahme sofort (nicht erst auf GPIO Button)
    press long Button for Start of Record
    press long Button for Start/Stop of Record
    Ctrl+C beendet Aufnahme und Programm

## `./install/`

hier befinden sich Skripte zur Installation des BT-Moduls.

### `./install/bt_pair_BC127.exp`

hierzu:
    [BC127 Basics](https://learn.sparkfun.com/tutorials/understanding-the-bc127-bluetooth-module/all)

[Expect Skripting](https://linux.die.net/man/1/expect)

das Skript übernimmt das Pairen via UART Verbindung.

### `./install/raspberry_InCarSensors_and_bt_installer.sh`
...
# Das erste mal Booten
## ausführen des `./install.sh` skripts

**Dabei netzwerk/ internet, und telemetrie/ platine verbindung sicherstellen (via UART /FTDI Adapter).**
Hierbei auf die richtige Polung von VCC und GND und von RX/TX achten. 
Es kann sein, dass das Pairing fehlschlägt.
Dann kann das Skript `./install.sh` erneut aufgerufen werden. nach einem Neustart und eingeschaltetem ATM Modul wird automatisch eine Bluetooth Verbindung aufgebaut.

## SSH Login

Login via `ssh pi@raspberrypi` oder `ssh pi@IP_ADRESSE`
Passwort entweder `pipi1234` oder `raspberry`.

## SSH File Access

    sshfs pi@raspberrypi:DIRECTORY_ON_RASPI DIRECTORY_TO_MOUNT_ON_PC

Mountet mithilfe von FUSE den raspi Ordner wie ein Netzwerklaufwerk.
ermöglicht das direkte editieren von Dateien auf dem Raspi unter MacOS oder Linux. (Zb. mit IDEs oder Spacemacs, VS Code ...)

 Windows Alternativ:

 [WinSCP](https://winscp.net/eng/docs/lang:de)
oder ähnliche tools.
# Hardware

Das ATM Modul wird durch "Schütteln" oder Rotation aktiviert.
 Es kann auch eine Direkte Steckverbindung von Batterie und BC127 zum Dauerbetrieb hergestellt werden. 
 Die BL Verbindung wird automatisch hergestellt.
Dann kann Die BT-Audio bspw. via `./Programs/control/gpio-event-load-bt-audio.py` aufgenommen werden.

# hilfreiche Tools im CLI/Terminal

sudo apt install...

File Manager:

    mc
    ranger

Network Manager:

    wicd-curses

Editors:

    vim
    nano
    emacs

https://vimawesome.com --> Vim Plugins

https://github.com/amix/vimrc --> akzeptable Vim config. ohne YouCompleteMe.

git:

    git-lfs
SSH:

    ssh
    sshfs
Shell:

    zsh
    oh-my-zsh

