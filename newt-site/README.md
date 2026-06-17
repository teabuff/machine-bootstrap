# newt-site — Dockerized Newt connector for a site/homelab host

Optional add-on (not part of the `host/` hub). Runs a [Newt](https://github.com/fosrl/newt)
connector on a machine behind NAT/CGNAT so its local services become Pangolin resources —
the box dials *out* to the hub, nothing inbound.

```sh
cp .env.example .env        # set PANGOLIN_ENDPOINT + NEWT_PROVISIONING_KEY
docker compose up -d
```

- **Self-registration:** on first boot Newt swaps the one-time `NEWT_PROVISIONING_KEY`
  (generated once on the hub) for its own id/secret, persists them to `newt-data/`, and
  wipes the key — so the same key can seed a fleet without per-site copy/paste.
- **Declarative resources (opt-in):** drop a blueprint (see `example.blueprint.yaml`) and
  set `NEWT_BLUEPRINT_FILE` in `docker-compose.yml`; Newt reconciles it continuously —
  headless, no API key, because Newt is already an authenticated site.

`.env` and `newt-data/` are gitignored.
