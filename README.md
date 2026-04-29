# ices-advice.taf-universe

## Publishing Stocks on ices-advice

When publishing a stock to the `ices-advice` github organisation, the github workflow does the following for each stock listed in `repositories.json`

```mermaid
flowchart TD

REPOS([For each stock in repositories.json])

REPOS --> LOOP[/Start loop over ices-taf repos/]

LOOP --> CLONE[Clone repo into subfolder of temp folder]
CLONE --> CLEAN["Clean repository<br/>(remove git, data, misc files)"]

CLEAN --> SAFE{Publish boot data?}

SAFE -->|Yes| RUN{Run assessment?}
SAFE -->|No| MORE


RUN -->|Yes| BOOT[["taf.boot()"]]
RUN -->|No| MORE[["taf.boot()"]]

BOOT --> SOURCE[["source.all()"]]


SOURCE --> MORE{More repos?}
MORE -->|Yes| LOOP
MORE -->|No| COMMIT

COMMIT[Commit & force push to GitHub] --> OPEN([Open repo in browser])
```

An example repositories.json file is:

```json
[
  {
    "repo_name": "2026_san.sa.1r",
    "repos": ["2026_san.sa.1r_assessment"],
    "subdir": [""],
    "year": 2026,
    "safe": true,
    "run": false
  },
  {
    "repo_name": "2026_san.sa.2r",
    "repos": ["2026_san.sa.2r_assessment"],
    "subdir": [""],
    "year": 2026,
    "safe": true,
    "run": false
  },
  {
    "repo_name": "2026_san.sa.3r",
    "repos": ["2026_san.sa.3r_assessment"],
    "subdir": [""],
    "year": 2026,
    "safe": true,
    "run": false
  }
]
```
