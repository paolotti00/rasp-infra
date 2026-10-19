# dobby-map

Tiny localhost service that turns the Ecovacs "Dobby" vacuum map into a PNG, so Home Assistant can send it to Telegram.

## Why
`image.dobby_map` (Home Assistant) is an **SVG**; Telegram rejects SVG as a photo (`Image_process_failed`). The Home Assistant container has no SVG renderer, so conversion runs on the host.

## How it works
- `dobby_map_service.py` listens on `127.0.0.1:8765` (stdlib only).
- `GET /render?path=<entity_picture of image.dobby_map>`: downloads the SVG from Home Assistant (the `entity_picture` URL already carries its access token, so no HA token is needed), converts it with `rsvg-convert` and writes `/home/pi/homeassistant/www/dobby_map.png` (`/config/www/dobby_map.png` inside the HA container).
- Only paths starting with `/api/image_proxy/image.dobby_map` are accepted.
- Home Assistant side: a `rest_command.dobby_render_map` calls the service, then `telegram_bot.send_photo` sends the file (automation `Dobby vacuum notifications` in `automations.yaml`).

## Install
```bash
sudo apt-get install -y --no-install-recommends librsvg2-bin
sudo cp dobby-map.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now dobby-map.service
```

## Test
```bash
P=$(curl -s -H "Authorization: Bearer $HA_TOKEN" http://127.0.0.1:8123/api/states/image.dobby_map | python3 -c "import sys,json;print(json.load(sys.stdin)['attributes']['entity_picture'])")
curl -G --data-urlencode "path=$P" http://127.0.0.1:8765/render   # -> ok
ls -l /home/pi/homeassistant/www/dobby_map.png
```
