#!/usr/bin/env bash
# scripts/check-sops.sh
set -euo pipefail

exit_code=0

for file in "$@"; do
    # пропускаем несуществующие (удалённые) файлы
    [[ -f "$file" ]] || continue

    # количество документов в файле
    doc_count=$(yq eval-all '. as $item ireduce (0; . + 1)' "$file" 2>/dev/null || echo 0)

    for ((i=0; i<doc_count; i++)); do
        kind=$(yq eval "select(documentIndex == $i) | .kind" "$file" 2>/dev/null)

        if [[ "$kind" == "Secret" ]]; then
            has_sops=$(yq eval "select(documentIndex == $i) | has(\"sops\")" "$file" 2>/dev/null)

            if [[ "$has_sops" != "true" ]]; then
                name=$(yq eval "select(documentIndex == $i) | .metadata.name // \"<unnamed>\"" "$file")
                echo "❌ $file: Secret '$name' (doc #$i) НЕ зашифрован SOPS (нет поля 'sops')"
                exit_code=1
            fi
        fi
    done
done

if [[ $exit_code -eq 0 ]]; then
    echo "✅ Все Secret зашифрованы SOPS"
fi

exit $exit_code
