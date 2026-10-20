# Rizzo Flow API

Rizzo Flow dietro un `docker-compose.yml` riutilizzabile: typed decisions e stime numeriche
locali con Spark-X2.5-4B, senza generazione di token, servite su `http://127.0.0.1:8017`.

L'immagine contiene solo l'app (~500 MB): il runtime llama.cpp (30 MB) e i pesi GGUF
(~4.4 GB) vengono scaricati **al primo avvio** dentro `./data/`, quindi restano tra un
`down` e l'altro, tra un rebuild e l'altro, e l'immagine non diventa enorme.

```
rizzo-flow/
├── docker-compose.yml       base: CPU, nessun device passato al container
├── docker-compose.gpu.yml   overlay: AMD/Intel via Vulkan (/dev/dri)
├── Dockerfile               build con uv --locked da un commit pinnato
├── docker/entrypoint.sh     download al primo avvio + serve
├── Makefile                 scorciatoie (make up / logs / health / update)
├── .env.example             tutte le manopole, ogni valore ha un default
└── data/                    creato al primo avvio: modelli, runtime, cache HF
```

## Uso

```bash
cd rizzo-flow
make up          # GPU Vulkan se /dev/dri esiste, altrimenti CPU; build + download al primo giro
make logs        # segui il download e poi lo startup (il modello carica in ~10 s)
make health      # {"status":"ready", "model": {... device: "gpu", backend: "vulkan"}}
```

Poi:

- playground: <http://127.0.0.1:8017/playground>
- OpenAPI docs: <http://127.0.0.1:8017/docs>
- API: `POST /v1/decisions`, `POST /v1/systemone`, `GET /v1/models`, `GET /health`

```bash
curl -s http://127.0.0.1:8017/v1/systemone \
  -H 'Content-Type: application/json' \
  -d '{
    "state": "Il mio pagamento è fallito da 3 giorni e ho una scadenza oggi.",
    "model": "rizzo-latest",
    "questions": {
      "is_urgent": {"type": "noul", "instructions": "Il messaggio trasmette urgenza?"},
      "reparto": {"type": "choice", "instructions": "Quale reparto deve gestirlo?",
        "criteria": {"billing": "Pagamenti, fatture, rimborsi", "technical": "Bug e disservizi", "sales": null}},
      "frustrazione": {"type": "score", "instructions": "Quanto è frustrato il cliente?",
        "criteria": ["Calmo", "Frustrato", "Molto arrabbiato"]}
    }
  }' | python3 -m json.tool
```

Senza `make`, gli stessi comandi in chiaro:

```bash
docker compose -f docker-compose.yml -f docker-compose.gpu.yml up -d   # GPU
docker compose -f docker-compose.yml up -d                             # CPU
```

Su questa macchina `docker` è podman (`/usr/bin/docker` → `podman`), quindi `docker compose`
passa da `podman-compose`: entrambi i file funzionano così.

## GPU (qui: AMD RX 6650 XT)

`docker-compose.gpu.yml` passa `/dev/dri` e imposta `RIZZO_RUNTIME=vulkan`. Lo stack Vulkan
sta nell'immagine (`libvulkan1` + `mesa-vulkan-drivers`), il driver kernel resta quello
dell'host: niente NVIDIA, niente toolkit CUDA.

- **podman rootless**: `RIZZO_GROUP_ADD=keep-groups` (default), così il container eredita i
  tuoi gruppi `render`/`video`.
- **docker**: `getent group render` e metti il GID in `.env` → `RIZZO_GROUP_ADD=987`.
- Se la GPU non viene enumerata, `--device auto` ricade sulla CPU senza far fallire l'avvio
  (`/health` mostra `device` e `backend` reali).
- Host senza `/dev/dri`: `make` non aggiunge l'overlay e parte in CPU.

## Manopole (`.env`)

| Variabile | Default | Note |
| --- | --- | --- |
| `RIZZO_PORT` / `RIZZO_HOST` | `8017` / `127.0.0.1` | `0.0.0.0` solo se vuoi esporla in LAN |
| `RIZZO_SIZE` | `4b` | `1.7b` è 2× più veloce e molto meno accurato |
| `RIZZO_QUANT` | `q8_0` | `q8_0` 4.4 GB · `q4_k_m` 2.6 GB · `bf16` 8.2 GB |
| `RIZZO_WEIGHTS` | `flow` | `base` = Spark-X2.5 originale |
| `RIZZO_CTX` | `8192` | token per domanda; input più lunghi vengono rifiutati |
| `RIZZO_BATCH_SIZE` | `4` | domande in un micro-batch |
| `RIZZO_THREADS` | — | solo con `RIZZO_RUNTIME=cpu` |
| `RIZZO_KV_TYPE` | — | `q8_0`/`q4_0` se un `RIZZO_CTX` lungo non entra in VRAM |
| `RIZZO_API_KEY` | vuoto | se impostata, Bearer auth su `/v1/systemone` e `/v1/models` |
| `RIZZO_RUNTIME` / `RIZZO_DEVICE` | `cpu`/`cpu`, `vulkan`/`auto` con GPU | forzabili qui |
| `RIZZO_COMMIT` | commit pinnato | commit upstream costruito dall'immagine |

Cambiando `RIZZO_SIZE`/`QUANT`/`WEIGHTS`/`RUNTIME` il container riscarica solo i file
mancanti (nuovo stamp `.ready-*` in `./data`); per forzare la rivalidazione completa
`RIZZO_FORCE_DOWNLOAD=1 docker compose up -d`.

## Comandi utili

```bash
make update      # rebuild sull'ultimo commit upstream + restart
make build       # rebuild (i pesi in ./data non si toccano)
make shell       # bash nel container: rizzo decide examples/ticket.json, rizzo schema, ...
make down        # stop + rm container, ./data resta
make clean-data  # cancella ./data (riscarica 4.4 GB al prossimo avvio)
```

Passare da `make up` a `make up-cpu` (e viceversa) ricrea il container da solo: non serve un
`make down` prima.

## Misure su questa macchina (Q8_0, ctx 8192)

| | 3 domande (noul + choice + score) | picco VRAM |
| --- | --- | --- |
| `make up` — RX 6650 XT, Vulkan | **1.7 s** | 6.0 GB |
| `make up-cpu` — i5-8400, 6 thread | ~7.6 s per 2 domande | — |

Caricamento del modello a ogni avvio: ~17 s (include l'hash di verifica del GGUF). Con 8 GB di
VRAM il Q8_0 a `RIZZO_CTX=8192` ci sta; se alzi il contesto e non entra, `RIZZO_KV_TYPE=q8_0`.

## Note

- Il container ascolta su `0.0.0.0:8017` **dentro** il container; verso l'host il mapping è
  limitato a `127.0.0.1` per default.
- Bind mount `./data:/data`: il container ci scrive come root mappato sul tuo utente (podman
  rootless), quindi i file restano tuoi.
- La prima `make up` scarica ~4.4 GB: l'healthcheck ha `start_period: 30m` per non segnare il
  container come malato durante il download.
- Non c'è `depends_on` né altro servizio: è un'API standalone che puoi far puntare da qualsiasi
  altro compose con `http://rizzo-flow:8017` se la metti sulla stessa rete.
