# Guided Implementation Workflow

## State machine

| State | Разрешённые изменения | Обязательный артефакт | Выход из состояния |
| --- | --- | --- | --- |
| `INTAKE` | Только `.agent-flow/tasks/<id>/` | `brief.md` | Scope и risk определены |
| `DISCOVERY` | Только task-документы | `discovery.md` | Текущий flow и варианты понятны |
| `WAIT_PLAN_APPROVAL` | Только task-документы | `plan.md` | Человек явно утвердил plan |
| `IMPLEMENTING_SLICE_N` | Утверждённый scope slice | code, tests, `progress.md` | Проверки выполнены |
| `WAIT_SLICE_APPROVAL` | Только исправления, явно запрошенные человеком | diff/evidence/handoff update | Человек принял slice или запросил изменения |
| `REVIEW` | Reviewer не меняет code | `review.md` | Findings рассмотрены |
| `OWNERSHIP_GATE` | Только согласованные fixes/docs | `handoff.md` | Человек прошёл ownership-check |
| `DONE` | Нет | финальные task-документы | Готово к merge/merged |
| `BLOCKED` | Только безопасная диагностика | причина в `progress.md` | Получено решение/доступ |

Нельзя перескакивать из `DISCOVERY` прямо в реализацию. Обещание агента, зелёный
тест или готовность tool call не заменяют human approval.

## 0. Project bootstrap

Выполняется один раз или при устаревшей карте проекта:

1. Следовать `prompts/bootstrap.md`.
2. Исследовать repo layout, build/test commands, entry points и CI.
3. Заполнить `PROJECT.md`, маркируя неизвестное.
4. Показать человеку архитектурную карту, инварианты и вопросы.
5. После исправлений человек меняет статус на `HUMAN_APPROVED`.

Bootstrap не должен перерабатывать приложение или «попутно улучшать» код.

## 1. Intake

Создать task-папку через `bin/flow new <slug>` и заполнить `brief.md`:

- problem и наблюдаемое текущее поведение;
- desired behavior и acceptance criteria;
- non-goals;
- ограничения;
- risk class;
- известные человеческие решения.

Если постановка двусмысленна, задать минимальное число вопросов до discovery.

## 2. Discovery — read-only относительно продукта

Исследовать только релевантные части системы. Зафиксировать в `discovery.md`:

- entry point → control/data flow → side effects;
- существующие patterns и похожие реализации;
- внешние контракты, consumers и инварианты;
- observability и failure modes;
- тестовый harness;
- 2–3 варианта с trade-offs;
- рекомендацию и открытые вопросы.

Не писать production-код, тесты реализации, миграции или новые abstractions.
Допустимы только task-документы и безопасные read-only команды.

## 3. Plan и первый human gate

Сформировать `plan.md` из independently reviewable vertical slices. Каждый
slice должен:

- давать связное, проверяемое поведение либо безопасную подготовку;
- сохранять green build;
- иметь явные файлы/границы и acceptance tests;
- укладываться в budget либо иметь согласованное исключение;
- указывать observability и rollback;
- не оставлять orphaned/dead code.

Для architecture/schema/API/security решений создать decision record из
`templates/decision.md`.

Затем остановиться. Начинать реализацию можно только после явного ответа вроде
`утверждаю plan` или `реализуй slice 1`.

## 4. Slice loop

Для одного утверждённого slice:

1. Проверить чистоту/состояние working tree и не перезаписывать чужие изменения.
2. Зафиксировать ожидаемое поведение тестом или воспроизводимым сценарием.
3. Реализовать минимальное решение в согласованных границах.
4. Выполнить узкие проверки, затем релевантный полный набор из `PROJECT.md`.
5. Запустить `bin/flow budget` для текущего diff или нужного range.
6. Просмотреть diff на scope creep, dead code, debug output и случайные файлы.
7. Обновить `progress.md` и `handoff.md`.
8. Представить checkpoint:
   - цель slice;
   - изменённый flow;
   - diffstat и budget categories;
   - сохранённые инварианты;
   - команды и результаты;
   - риски/непроверенное;
   - следующий slice.
9. Остановиться в `WAIT_SLICE_APPROVAL`.

Если человек запросил исправление, не расширять scope. После acceptance сделать
один смысловой commit. Следующий slice начинается только по новому разрешению.

## 5. Verification и independent review

После последнего slice:

1. Сопоставить итоговый diff с `brief.md` и утверждённым `plan.md`.
2. Выполнить полный релевантный набор проверок.
3. Провести ручной/smoke scenario; для UI приложить screenshot/video, если
   инфраструктура проекта это допускает.
4. В свежей сессии или отдельным reviewer-agent выполнить
   `prompts/review.md` и сохранить результат в `review.md`.
5. Для каждого finding: подтвердить evidence, исправить отдельным узким slice
   либо явно принять residual risk.

Reviewer не должен сначала читать авторский самоотчёт как доказательство. Он
начинает с требований, diff и исполняемого поведения, затем использует handoff
для проверки полноты.

## 6. Ownership gate

Обновить `handoff.md` и пройти `.agent-flow/OWNERSHIP.md`. Цель — не запомнить
все строки, а уметь:

- провести запрос/событие через изменённые компоненты;
- назвать ключевые инварианты и места принятия решений;
- предсказать failure behavior;
- найти проблему по логам/метрикам;
- безопасно отключить или откатить изменение.

Если человек не может этого сделать, агент объясняет систему по реальному коду,
задаёт проверочные вопросы и при необходимости уменьшает/упрощает изменение.

## 7. Close

Перед `DONE`:

- обновить state в `brief.md` и `progress.md`;
- записать final evidence и residual risks;
- удалить временный debug code и неиспользуемые artifacts;
- убедиться, что task-документы не содержат secrets/PII;
- дать короткий merge/rollback handoff.

CI, Sonar/quality gates и automated review считаются страховочными слоями, а не
доказательством человеческого понимания.

