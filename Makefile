export KUBECONFIG := ./.private-files/gilfoyle.yaml

# --- HAProxy переменные ---
HAPROXY_NS := haproxy-ingress
HAPROXY_SELECTOR := app.kubernetes.io/name=haproxy-ingress
HAPROXY_SOCK := /run/haproxy/admin.sock
HONEYPOT_NS := honeypot

.PHONY: debug status check-git check-ks check-helm logs lint reconcile \
        hap-tables hap-banned hap-watch hap-unban hap-ban hap-clear \
        hap-logs hap-honeypot-logs hap-top hap-help \
        geoip-build geoip-push

# Основная команда: Полная диагностика
debug: status check-git check-ks check-helm logs

# Общий статус всех ресурсов Flux
status:
	@printf "\n🚀 --- General Flux Resources ---\n"
	@flux get all -A

# Проверка источников (Git / Helm Repos)
check-git:
	@printf "\n🛠 --- Git Repositories Status ---\n"
	@kubectl get gitrepositories -A -o custom-columns="NAME:.metadata.name,REVISION:.status.artifact.revision,READY:.status.conditions[?(@.type=='Ready')].status,MESSAGE:.status.conditions[?(@.type=='Ready')].message"

# Проверка сборки Kustomizations
check-ks:
	@printf "\n🧩 --- Kustomizations Status (Manifest Build) ---\n"
	@kubectl get kustomizations -A -o custom-columns="NAME:.metadata.name,PATH:.spec.path,READY:.status.conditions[?(@.type=='Ready')].status,MESSAGE:.status.conditions[?(@.type=='Ready')].message"

# Проверка Helm релизов
check-helm:
	@printf "\n⚓ --- Helm Releases Status ---\n"
	@kubectl get helmreleases -A -o custom-columns="NAME:.metadata.name,READY:.status.conditions[?(@.type=='Ready')].status,MESSAGE:.status.conditions[?(@.type=='Ready')].message"

# Последние ошибки из всех контроллеров Flux
logs:
	@printf "\n📝 --- Last 20 error logs from Flux controllers ---\n"
	@kubectl logs -n flux-system -l "control-plane in (controller, helm-controller, source-controller, kustomize-controller)" --tail=200 | grep -iE "error|fail|already registered" | tail -n 20 || echo "Logs are clean."

# Локальная проверка сборки ПЕРЕД пушем в Git
lint:
	@printf "\n🔍 --- Local Kustomize Lint ---\n"
	@kustomize build 01-flux/gilfoyle/flux-system > /dev/null && echo "✅ Build successful" || echo "❌ Build failed - check paths and duplicates!"

# Принудительный "пинок" Flux
reconcile:
	@printf "\n🔄 --- Forcing Flux Reconcile ---\n"
	flux reconcile source git flux-system
	flux reconcile kustomization flux-system --with-source

# ============================================================
#  HAPROXY / BAN MANAGEMENT
# ============================================================

# Хелпер: получить имя пода HAProxy в переменную внутри рецепта
define HAP_POD
$(shell kubectl get pods -n $(HAPROXY_NS) -l $(HAPROXY_SELECTOR) -o jsonpath='{.items[0].metadata.name}')
endef

# Хелпер: выполнить Runtime API команду. Использование: $(call hapcmd,show table)
define hapcmd
kubectl exec -n $(HAPROXY_NS) $(HAP_POD) -c haproxy-ingress -- sh -c "echo '$(1)' | socat stdio $(HAPROXY_SOCK)"
endef

# Показать все stick-tables (http + https)
hap-tables:
	@printf "\n📊 --- HAProxy Stick Tables ---\n"
	@printf "\n--- _front_http ---\n"
	@$(call hapcmd,show table _front_http)
	@printf "\n--- _front_https ---\n"
	@$(call hapcmd,show table _front_https)

# Показать ТОЛЬКО забаненных (gpc0 > 0)
hap-banned:
	@printf "\n🚫 --- BANNED IPs (gpc0 > 0) ---\n"
	@printf "\n--- HTTP ---\n"
	@$(call hapcmd,show table _front_http data.gpc0 gt 0) || echo "none"
	@printf "\n--- HTTPS ---\n"
	@$(call hapcmd,show table _front_https data.gpc0 gt 0) || echo "none"

# Live-наблюдение за забаненными (обновление каждые 3 сек)
hap-watch:
	@printf "\n👁  --- Watching banned IPs (Ctrl+C to stop) ---\n"
	@POD=$$(kubectl get pods -n $(HAPROXY_NS) -l $(HAPROXY_SELECTOR) -o jsonpath='{.items[0].metadata.name}'); \
	while true; do \
		clear; \
		echo "=== BANNED @ $$(date '+%H:%M:%S') ==="; \
		echo "--- HTTP ---"; \
		kubectl exec -n $(HAPROXY_NS) $$POD -c haproxy-ingress -- sh -c "echo 'show table _front_http data.gpc0 gt 0' | socat stdio $(HAPROXY_SOCK)"; \
		echo "--- HTTPS ---"; \
		kubectl exec -n $(HAPROXY_NS) $$POD -c haproxy-ingress -- sh -c "echo 'show table _front_https data.gpc0 gt 0' | socat stdio $(HAPROXY_SOCK)"; \
		sleep 3; \
	done

# Снять бан с IP на обоих фронтендах. Использование: make hap-unban IP=1.2.3.4
hap-unban:
	@if [ -z "$(IP)" ]; then echo "❌ Usage: make hap-unban IP=1.2.3.4"; exit 1; fi
	@printf "\n♻️  --- Unbanning $(IP) ---\n"
	@$(call hapcmd,clear table _front_http key $(IP))
	@$(call hapcmd,clear table _front_https key $(IP))
	@echo "✅ $(IP) unbanned (http + https)"

# Забанить IP вручную. Использование: make hap-ban IP=1.2.3.4
hap-ban:
	@if [ -z "$(IP)" ]; then echo "❌ Usage: make hap-ban IP=1.2.3.4"; exit 1; fi
	@printf "\n🔨 --- Banning $(IP) ---\n"
	@$(call hapcmd,set table _front_http key $(IP) data.gpc0 1)
	@$(call hapcmd,set table _front_https key $(IP) data.gpc0 1)
	@echo "✅ $(IP) banned (http + https) → hellpot"

# Полностью очистить обе таблицы (снять ВСЕ баны)
hap-clear:
	@printf "\n🧹 --- Clearing ALL stick tables ---\n"
	@$(call hapcmd,clear table _front_http)
	@$(call hapcmd,clear table _front_https)
	@echo "✅ All tables cleared"

# Логи доступа HAProxy (контейнер access-logs)
hap-logs:
	@printf "\n📝 --- HAProxy access logs (last 50) ---\n"
	@kubectl logs -n $(HAPROXY_NS) $(HAP_POD) -c access-logs --tail=50

# Логи honeypot (hellpot) — кого поймали в ловушку
hap-honeypot-logs:
	@printf "\n🍯 --- Hellpot honeypot logs (last 50) ---\n"
	@kubectl logs -n $(HONEYPOT_NS) -l app=hellpot --tail=50 || \
		kubectl logs -n $(HONEYPOT_NS) deploy/hellpot --tail=50

# Топ самых злостных по gpc0 (HTTPS), отсортированный
hap-top:
	@printf "\n🏆 --- Top offenders by gpc0 (HTTPS) ---\n"
	@$(call hapcmd,show table _front_https data.gpc0 gt 0) | \
		grep -oE 'key=[0-9.]+ .*gpc0=[0-9]+' | \
		sed -E 's/key=([0-9.]+).*gpc0=([0-9]+)/\2 \1/' | \
		sort -rn | head -20 | awk '{printf "  %-5s %s\n", $$1, $$2}' || echo "none"

# Справка по HAProxy командам
hap-help:
	@printf "\n⚙️  --- HAProxy / Ban Management Commands ---\n"
	@echo "  make hap-tables        — показать все stick-tables целиком"
	@echo "  make hap-banned        — показать только забаненных (gpc0>0)"
	@echo "  make hap-watch         — live-мониторинг забаненных"
	@echo "  make hap-top           — топ-20 злостных сканеров"
	@echo "  make hap-ban IP=x.x.x.x    — забанить IP вручную"
	@echo "  make hap-unban IP=x.x.x.x  — снять бан с IP"
	@echo "  make hap-clear         — снять ВСЕ баны (очистить таблицы)"
	@echo "  make hap-logs          — логи доступа HAProxy"
	@echo "  make hap-honeypot-logs — логи hellpot (пойманные жертвы)"

# ============================================================
#  GEOIP BACKEND — build & push
# ============================================================

GEOIP_DIR := 01-flux/gilfoyle/apps/haproxy-ingress/geoip-backend
GEOIP_IMAGE := ghcr.io/split174/geoip-lookup:latest

geoip-build:
	@printf "\n🔨 --- Building GeoIP backend image ---\n"
	docker build -t $(GEOIP_IMAGE) $(GEOIP_DIR)
	@echo "✅ Image built: $(GEOIP_IMAGE)"

geoip-push: geoip-build
	@printf "\n📤 --- Pushing GeoIP backend image ---\n"
	docker push $(GEOIP_IMAGE)
	@echo "✅ Image pushed to ghcr.io"
