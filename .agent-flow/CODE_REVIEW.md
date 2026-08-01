# Risk-Based Code Review

Reviewer сообщает только конкретные actionable findings с evidence. Не нужно
пересказывать diff или хвалить корректные части. Если findings нет — так и
скажи, перечислив проверенный scope и оставшиеся ограничения.

## Порядок review

1. **Intent:** соответствует ли diff `brief.md` и утверждённому `plan.md`; нет ли
   скрытого scope creep.
2. **Behavior:** корректны ли happy path, edge cases, retries, errors и partial
   failures.
3. **Contracts:** совместимы ли API, schema, events, serialization и внешние
   consumers.
4. **State:** корректны ли transactions, concurrency, idempotency, ordering,
   caching и consistency.
5. **Security:** authn/authz, validation, injection, secrets, PII, logging и
   least privilege.
6. **Operations:** timeouts, cancellation, resource cleanup, observability,
   deploy и rollback.
7. **Maintainability:** следует ли код существующим patterns; нет ли лишней
   abstraction, dependency, duplication, dead code и magic behavior.
8. **Verification:** действительно ли тесты способны обнаружить регрессию; тест
   ключевого поведения должен падать при удалении реализации.

## Формат finding

```text
[P0|P1|P2|P3] Короткое название
Где: path:line или точный symbol
Условие: конкретный вход/состояние, при котором проявляется проблема
Последствие: наблюдаемая ошибка или риск
Evidence: код, тест, контракт или воспроизводимый сценарий
Safe path: минимальный способ исправления
```

- `P0`: потеря данных, security breach, массовая недоступность; merge запрещён.
- `P1`: вероятный серьёзный production bug или breaking change; merge запрещён.
- `P2`: локальная корректность/надёжность; обычно исправить до merge.
- `P3`: полезное улучшение без доказанного дефекта; не блокирует.

Не выдавай style preference за defect. Formatting/lint должны проверяться
автоматически. Не предлагай большой refactor, если безопасно исправить локально.

## Обязательные cross-checks

- Сравнить изменённые публичные контракты с consumers и compatibility rules.
- Найти новые dependencies, migrations, flags и configuration.
- Проверить negative/permission paths, а не только happy path.
- Проверить логи на secrets/PII и наличие diagnostic context.
- Проверить, что rollback не требует неизвестной необратимой операции.
- Отдельно перечислить то, что нельзя было выполнить или подтвердить.

## Независимость

По возможности review выполняется свежей сессией с `brief.md`, `plan.md`,
`PROJECT.md`, base ref и diff. Reviewer не редактирует файлы до решения человека.
Самопроверка автора полезна, но не считается независимым review.

