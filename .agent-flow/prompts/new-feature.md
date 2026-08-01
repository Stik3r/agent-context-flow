# Prompt: Новая фича или существенный bugfix

Прочитай `AGENTS.md`, `PROJECT.md`, `POLICY.md` и `WORKFLOW.md`.

1. Если `PROJECT.md` не имеет статуса `HUMAN_APPROVED`, остановись и предложи
   bootstrap.
2. Создай task-папку командой `.agent-flow/bin/flow new <короткий-slug>`.
3. Заполни `brief.md` из запроса пользователя. Не додумывай acceptance criteria;
   задай вопросы, если разные ответы меняют поведение или архитектуру.
4. Проведи read-only discovery и заполни `discovery.md`.
5. Предложи 2–3 решения, trade-offs и рекомендацию.
6. Разбей выбранное решение на independently reviewable slices в `plan.md`.
7. Отдельно выдели dependencies, schema/API/security/deployment решения,
   требующие approval.
8. Покажи краткое резюме discovery и plan, затем остановись в
   `WAIT_PLAN_APPROVAL`.

Не меняй production-код и тесты реализации до явного утверждения plan.

