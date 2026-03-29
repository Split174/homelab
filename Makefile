# Путь к твоему конфигу
export KUBECONFIG := ./.private-files/gilfoyle.yaml

.PHONY: debug status check-git check-ks check-helm logs lint reconcile

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
