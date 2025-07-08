# frankensteam
run steam in a container with nvidia graphics with remote sunshine

### podman cli

```bash
podman run -d \
  --name=frankensteam \
  --security-opt seccomp=unconfined \
  -e PUID=1000 \
  -e PGID=1000 \
  -e DRINODE=/dev/dri/renderD128 \
  -p 47984-47990:47984-47990  \
  -p 48010-48010:48010-48010 \
  -p 47998-48000:47998-48000/udp \
  -v /path/to/config:/config \
  -v /dev/input:/dev/input `#optional` \
  -v /run/udev/data:/run/udev/data `#optional` \
  --device /dev/dri:/dev/dri \
  --shm-size="1gb" \
  --restart unless-stopped \
  frankensteam
```
