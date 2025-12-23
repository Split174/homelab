# My HomeLab

### Deploy age key for flux

```bash
cat <path/to/age>/age.key |
kubectl create secret generic sops-age \
--namespace=flux-system \
--from-file=age.agekey=/dev/stdin
```

### Encrypt/Rewrite

```
export SOPS_AGE_KEY_FILE=<path/to/age>/age.key
sops 01-flux/gilfoyle/apps/dynamic-dns/secret.enc.yaml
```
