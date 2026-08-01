# Prompt: Продолжить работу

Не полагайся на память предыдущего чата.

1. Прочитай `AGENTS.md`, `PROJECT.md`, `POLICY.md`, `WORKFLOW.md`.
2. Запусти `.agent-flow/bin/flow status` и найди задачу, указанную пользователем.
   Если активных несколько и задача не названа — попроси выбрать.
3. Прочитай все Markdown-файлы выбранной task-папки и связанные decision records.
4. Сверь записанное состояние с `git status`, log и фактическим diff. Если они
   расходятся, остановись и опиши расхождение.
5. Дай резюме не длиннее 12 пунктов: goal, approved decisions, completed slices,
   evidence, current diff, blockers, residual risks и следующий gate.
6. Продолжай только из записанного state. Если state — `WAIT_*`, сначала дождись
   явного человеческого решения.

