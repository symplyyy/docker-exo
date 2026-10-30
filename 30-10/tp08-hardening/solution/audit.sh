#!/usr/bin/env bash
set -uo pipefail

PROJECT="${1:-}"
FILTER=()
[ -n "$PROJECT" ] && FILTER=(--filter "label=com.docker.compose.project=$PROJECT")

ids=$(docker ps -q "${FILTER[@]}")
[ -z "$ids" ] && { echo "aucun conteneur"; exit 0; }

total=0
printf '%-26s %-10s %-5s %-14s %-14s %-4s %-8s %-6s %-4s %-6s %s\n' CONTENEUR USER PRIV CAP_ADD CAP_DROP RO MEM PIDS NNP SOCKET ECARTS
for id in $ids; do
  IFS='|' read -r name user priv capadd capdrop ro mem pids secopt mounts < <(docker inspect "$id" --format \
    '{{.Name}}|{{.Config.User}}|{{.HostConfig.Privileged}}|{{join .HostConfig.CapAdd ","}}|{{join .HostConfig.CapDrop ","}}|{{.HostConfig.ReadonlyRootfs}}|{{.HostConfig.Memory}}|{{if .HostConfig.PidsLimit}}{{.HostConfig.PidsLimit}}{{else}}0{{end}}|{{join .HostConfig.SecurityOpt ","}}|{{range .Mounts}}{{.Source}} {{end}}')
  name=${name#/}
  ecarts=()
  case "$user" in ""|root|0|0:*) ecarts+=(root) ;; esac
  [ "$priv" = true ] && ecarts+=(privileged)
  [ -n "$capadd" ] && ecarts+=(cap_add)
  [[ ",$capdrop," == *",ALL,"* ]] || ecarts+=(cap_drop)
  [ "$ro" = true ] || ecarts+=(rootfs_rw)
  [ "$mem" = 0 ] && ecarts+=(no_mem_limit)
  [ "$pids" -le 0 ] && ecarts+=(no_pids_limit)
  [[ "$secopt" == *no-new-privileges* ]] || ecarts+=(nnp)
  sock=non
  [[ "$mounts" == *docker.sock* ]] && { sock=OUI; ecarts+=(docker_sock); }
  total=$((total + ${#ecarts[@]}))
  memh=$([ "$mem" = 0 ] && echo "-" || echo "$((mem / 1048576))M")
  printf '%-26s %-10s %-5s %-14s %-14s %-4s %-8s %-6s %-4s %-6s %s\n' "$name" "${user:-root}" "$priv" "${capadd:--}" "${capdrop:--}" \
    "$([ "$ro" = true ] && echo oui || echo non)" "$memh" "$([ "$pids" -le 0 ] && echo - || echo "$pids")" \
    "$([[ "$secopt" == *no-new-privileges* ]] && echo oui || echo non)" "$sock" "${ecarts[*]:-OK}"
done
echo "écarts : $total"
[ "$total" -eq 0 ]
