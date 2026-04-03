# Streambox Spotify Connect voor Raspberry Pi Zero W

Dit pakket maakt van een Raspberry Pi Zero W een lichte Spotify Connect ontvanger die je vanaf je telefoon kunt kiezen in de Spotify app.

## Wat zit erin?
- `setup_streambox_spotify.sh`  
  Automatische setup: installeert Java, Avahi, de Spotify Connect speler, schrijft de config en maakt een systemd service die automatisch start bij boot.
- `config.toml`  
  Voorbeeldconfig.
- `streambox-spotify.service`  
  Systemd servicebestand.

## Snel gebruik
1. Zet Raspberry Pi OS Lite op de Pi.
2. Zorg dat de gebruiker `streambox` bestaat.
3. Kopieer `setup_streambox_spotify.sh` naar de Pi.
4. Voer uit:
   ```bash
   chmod +x setup_streambox_spotify.sh
   sudo ./setup_streambox_spotify.sh
   ```
5. Reboot:
   ```bash
   sudo reboot
   ```
6. Open Spotify op je telefoon en kies apparaat `streambox`.

## Opmerkingen
- Spotify Premium is nodig voor Spotify Connect.
- De Pi Zero W is zwak spul. Daarom is de audiokwaliteit standaard op `HIGH` gezet in plaats van de maximale stand.
- Als je USB-audio gebruikt, moet je soms `mixerSearchKeywords` aanpassen in `config.toml`.
