# dvl-exchange-charts

Simple Express app that executes a few existing shell scripts from the repository and renders basic charts.

Quick start

1. Install dependencies from the `charts` folder:

```bash
cd charts
npm install
```

2. Copy `.env.example` to `.env` and adjust `DB_USER`/`DB_NAME` if needed.

3. Run:

```bash
npm start
```

Open `http://localhost:3002`.

Notes
- The server executes the existing `.sh` scripts in the repo root (for example `position.sh`, `cheapest.sh`).
- The UI attempts to parse pipe-delimited (`|`) output and will chart the first numeric column found.
