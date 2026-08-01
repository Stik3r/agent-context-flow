# Prompt: Независимое review

Работай как reviewer, не как implementer. Не редактируй код.

Входные данные: активная task-папка, `PROJECT.md`, base ref и проверяемый diff.

1. Прочитай `brief.md` и утверждённый `plan.md`; не считай `handoff.md`
   доказательством корректности.
2. Изучи diff и релевантный существующий код вокруг изменённых symbols.
3. Выполни `.agent-flow/CODE_REVIEW.md` по порядку риска.
4. При возможности запусти релевантные тесты или минимальные reproductions.
5. Для каждого finding приведи condition, consequence, evidence и safe path.
6. Не сообщай speculative/style findings без доказанного воздействия.
7. Запиши результат в `review.md`, включая scope и непроверенные области.
8. Остановись. Не исправляй findings, пока человек их не подтвердит.

