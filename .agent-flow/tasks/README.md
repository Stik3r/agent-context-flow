# Записи задач

Каждая нетривиальная задача получает папку вида:

```text
YYYYMMDD-HHMMSS-short-slug/
  brief.md
  discovery.md
  plan.md
  progress.md
  final-review.md
  handoff.md
  decisions/          # создаётся при необходимости
```

Task-папка — источник истины между agent sessions. Обновляй её после каждого
gate. Не сохраняй secrets, tokens, персональные данные, полные production logs
или крупные binaries.

Допустимые состояния: `INTAKE`, `DISCOVERY`, `WAIT_PLAN_APPROVAL`,
`IMPLEMENTING_SLICE_<N>`, `WAIT_SLICE_APPROVAL`, `VERIFYING`,
`WAIT_FINAL_HUMAN_REVIEW`, `CONTEXT_HANDOFF`, `BLOCKED`, `DONE`, `ABANDONED`.
Вместо `<N>` записывается положительный номер этапа, например
`IMPLEMENTING_SLICE_1`.

В task-папках старого формата может остаться `review.md`. Он не блокирует
валидацию, но при финализации нужно создать `final-review.md` по актуальному
шаблону.
