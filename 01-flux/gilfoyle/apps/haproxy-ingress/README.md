# HAProxy Ingress

HAProxy Ingress is an Ingress Controller that configures HAProxy to expose services to the outside world.

* [Site](https://haproxy-ingress.github.io/)
* [Documentation](https://haproxy-ingress.github.io/docs/)
* [Helm Chart](https://github.com/haproxy-ingress/charts)

## Configuration
Exposed via NodePort:
- HTTP: 30080
- HTTPS: 30443

## GeoIP (haproxy-lua-geoip2)

Enriches all incoming HTTP requests with geographic headers:
- `X-Geo-Country` — ISO country code (e.g., `RU`, `US`)
- `X-Geo-Continent` — continent code (e.g., `EU`, `NA`)
- `X-Geo-ASN` — AS number (e.g., `AS12345`)

### Setup

Базы GeoLite2 скачиваются из [P3TERX/GeoLite.mmdb](https://github.com/P3TERX/GeoLite.mmdb) (GitHub releases). **Регистрация в MaxMind не требуется.**

**sidecar** (`geoip-updater`) — при старте пода ждёт готовности HAProxy, скачивает базы, делает graceful reload. Затем обновляет базы **раз в 2 недели по крону** и снова reload.

Обновление происходит атомарно (download → `.mmdb.new` → `mv`), без даунтайма (HAProxy reload без обрыва соединений).

Geo-blocking работает в режиме **fail-open**: пока базы не загружены, трафик не блокируется. После первого reload'а блокировка включается.

### How it works

```mermaid
flowchart LR
    A[P3TERX/GeoLite.mmdb<br/>GitHub Releases] -->|"wget / cron 14d"| G[sidecar<br/>geoip-updater]
    G -->|atomic mv + reload| C[emptyDir: /var/lib/GeoIP]
    D[ConfigMap: haproxy-geoip-lua] -->|mmdb.lua, haproxy_mmdb.lua| E[/etc/haproxy/geoip/]
    C --> F[HAProxy]
    E --> F
    G -->|"echo reload | socat"| H[/var/run/haproxy-socket/admin.sock]
    H --> F
    F -->|lua.mmdb_lookup| I[X-Geo-Country, X-Geo-Continent, X-Geo-ASN]
```

### Troubleshooting

```bash
# Проверить, скачались ли базы
kubectl -n haproxy-ingress exec daemonset/haproxy-ingress -- ls -la /var/lib/GeoIP/

# Посмотреть логи sidecar (последние обновления, ошибки)
kubectl -n haproxy-ingress logs daemonset/haproxy-ingress -c geoip-updater --tail=50

# Следить за логами sidecar в реальном времени
kubectl -n haproxy-ingress logs daemonset/haproxy-ingress -c geoip-updater -f

# Ручной перекат баз (рестарт DaemonSet)
kubectl -n haproxy-ingress rollout restart daemonset/haproxy-ingress

# Проверить, что HAProxy подхватил базы (должен быть непустой X-Geo-Country)
kubectl -n haproxy-ingress exec daemonset/haproxy-ingress -- \
  sh -c 'echo "show info" | socat - UNIX-CONNECT:/var/run/haproxy-socket/admin.sock | head -20'
```
