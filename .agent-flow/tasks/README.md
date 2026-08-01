# Task records

Каждая нетривиальная задача получает папку вида:

```text
YYYYMMDD-HHMMSS-short-slug/
  brief.md
  discovery.md
  plan.md
  progress.md
  review.md
  handoff.md
  decisions/          # создаётся при необходимости
```

Task-папка — источник истины между agent sessions. Обновляй её после каждого
gate. Не сохраняй secrets, tokens, персональные данные, полные production logs
или крупные binaries.

Допустимые состояния: `INTAKE`, `DISCOVERY`, `WAIT_PLAN_APPROVAL`,
`IMPLEMENTING_SLICE_N`, `WAIT_SLICE_APPROVAL`, `REVIEW`, `OWNERSHIP_GATE`,
`BLOCKED`, `DONE`, `ABANDONED`.

