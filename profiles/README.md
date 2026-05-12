# `profiles/` — MEDC Incus profile templates

Each `*.yaml.tmpl` in this directory is a shell-`envsubst` template that
`medc apply` materialises into a real Incus profile and pushes via
`incus profile create | edit`. Profiles are **derived state** — never
hand-edit a profile inside Incus, the next `medc apply` will reconcile
it back to whatever this directory says.

## Templates shipped in v1

| Template | Role | Notes |
|---|---|---|
| `medc-base.yaml.tmpl`        | base       | Common cloud-init for every instance: packages, robot user + SSH keys, sshd posture, time sync, sysctls, swap-off. Also declares `eth0` on the Incus network. |
| `medc-gateway.yaml.tmpl`     | gateway    | The fat one. Standalone cloud-init (base content + gateway extras: dnsmasq, iptables NAT, tailscale subnet router, nginx binary host, dual-NIC eth0/eth1, persistent binaries-data disk). |
| `medc-mgmt.yaml.tmpl`        | mgmt       | Thin delta — sets the 8 GiB memory default. |
| `medc-k8s-control.yaml.tmpl` | k8s-control| Empty stub; reserved for future control-plane-specific tuning. |
| `medc-k8s-worker.yaml.tmpl`  | k8s-worker | Empty stub; reserved for future worker-specific tuning. |

## Composition

Every instance is created with two profiles applied in order:

```
incus init --profile medc-base --profile medc-<role> <name>
```

Incus profile composition merges scalar config keys (later profile
wins) and merges device entries by name. **It does NOT merge
multi-line string values** like `user.user-data`. That's why
`medc-gateway.yaml.tmpl` carries a *complete* cloud-init (base init +
gateway additions) rather than a delta — if it tried to set
`user.user-data` to just the gateway-specific bits, base's user-data
would be replaced wholesale and the OS init would never run.

## Templating convention

Variables use `${VAR}` syntax — straight `envsubst`. `medc apply`
exports each variable into the environment, then runs:

```
envsubst < profiles/medc-<role>.yaml.tmpl > /tmp/medc-<role>.yaml
incus profile edit medc-<role> < /tmp/medc-<role>.yaml
```

Variables consumed by these templates (full list documented at the
top of each `.yaml.tmpl`):

| Variable | Source / meaning |
|---|---|
| `MEDC_AUTHORIZED_KEYS_INDENTED` | Operator's SSH keys, pre-indented by `medc apply` for the `users[].ssh_authorized_keys` list location. |
| `MEDC_INCUS_NETWORK`            | Incus network name (`medcbr0`). |
| `MEDC_GATEWAY_IP_CIDR`          | Gateway's static lab-side IP, CIDR form (e.g. `10.0.3.5/24`). |
| `MEDC_LAB_SUBNET`               | Lab subnet CIDR (e.g. `10.0.3.0/24`). Tailscale advertise-route. |
| `MEDC_GATEWAY_HOSTNAME`         | Tailscale `--hostname` (e.g. `medc-gateway`). |
| `MEDC_TS_GATEWAY_AUTH_KEY`      | Tailscale auth key. From `connectivity.tailscale.gateway.auth_key_env`. |
| `MEDC_EGRESS_INTERFACE`         | Host NIC pulled into the gateway as `eth1` (macvlan parent). |
| `MEDC_DNSMASQ_CONFIG_INDENTED`  | Body of `/etc/medc/dnsmasq.conf`, pre-indented by `medc apply` for the cloud-init `write_files[].content: |` block scalar. |
| `MEDC_IPTABLES_V4_INDENTED`     | Body of `/etc/medc/iptables.rules.v4`, pre-indented similarly. |
| `MEDC_BINARIES_PATH`            | Filesystem path where binary host serves from. |
| `MEDC_BINARIES_DATA_SIZE`       | Incus disk device size for the binary host volume. |

## Why pre-indented multi-line variables?

Cloud-init's `write_files[].content: |` is a YAML block scalar. The
content must keep consistent indentation relative to the `content:`
key. If `medc apply` exported `MEDC_DNSMASQ_CONFIG` as raw multi-line
text, naive substitution would break YAML parsing — only the first
line would be at the right indent.

`medc apply` solves this by preparing the variable already-indented:

```
# In medc apply (pseudocode):
indent_for_yaml() {
    local indent="$1"
    sed "s/^/${indent}/"
}
export MEDC_DNSMASQ_CONFIG_INDENTED="$(
    render_dnsmasq_conf | indent_for_yaml '          '
)"
```

The template then just inserts the variable on its own line:

```yaml
      - path: /etc/medc/dnsmasq.conf
        content: |
${MEDC_DNSMASQ_CONFIG_INDENTED}
```

After substitution, every line of dnsmasq config sits at the right
indent and YAML parses cleanly.

## Validation before push

`medc apply` rendering pipeline:

1. `envsubst < profiles/medc-<role>.yaml.tmpl > <tmp>` (substitute).
2. `python3 -c 'import yaml,sys; yaml.safe_load(sys.stdin)' < <tmp>`
   (parse-check; fail fast if a substitution broke YAML).
3. `incus profile edit medc-<role> < <tmp>` (push).

A broken template aborts apply with exit code 1 (generic) before any
state mutation. A broken substituted YAML aborts with exit code 2
(config error).

## Adding new role profiles

1. Add a new role to the schema enum in `docs/v1-design.md` §3.3 and
   `config/medc.yaml.example`.
2. Create `profiles/medc-<new-role>.yaml.tmpl`. Start from
   `medc-k8s-worker.yaml.tmpl` as a thin-delta template.
3. Document the role in `medc-overview.md`'s topology section and add
   it to the validation in `medc apply` (PR4).

## Editing existing profiles

These templates are how MEDC's cloud-init evolves. Changes touch every
new instance after the next `medc apply`. Existing instances are NOT
reconciled — Incus profile changes don't re-run cloud-init on a
running instance. To apply profile changes operationally, either
recreate the instance or `incus exec` the relevant runcmd lines
manually.
