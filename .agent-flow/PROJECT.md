# Project Context

> Статус: `NOT_INITIALIZED`
>
> Заполни этот файл по `.agent-flow/prompts/bootstrap.md`, затем замени статус на
> `HUMAN_APPROVED` только после проверки человеком.

## Назначение системы

- Пользователи и их основная задача: `UNKNOWN`
- Критичные пользовательские сценарии: `UNKNOWN`
- Что считается недопустимым отказом: `UNKNOWN`

## Карта архитектуры

| Область | Ответственность | Entry points | Основные зависимости |
| --- | --- | --- | --- |
| `UNKNOWN` | `UNKNOWN` | `UNKNOWN` | `UNKNOWN` |

Опиши основной request/event/data flow от входа до внешнего side effect. Ставь
ссылки на реальные пути и символы, а не копируй большие фрагменты кода.

## Команды проекта

| Цель | Команда | Проверено | Примечание |
| --- | --- | --- | --- |
| Установка | `UNKNOWN` | Нет | |
| Локальный запуск | `UNKNOWN` | Нет | |
| Unit tests | `UNKNOWN` | Нет | |
| Integration tests | `UNKNOWN` | Нет | |
| Lint/format | `UNKNOWN` | Нет | |
| Type/static checks | `UNKNOWN` | Нет | |
| Build | `UNKNOWN` | Нет | |
| Quality/security | `UNKNOWN` | Нет | |

Не помечай команду проверенной, если она не была запущена в доступном окружении.
Если запуск невозможен, укажи причину.

## Доменные и технические инварианты

Для каждого правила укажи safe path — как правильно менять систему.

| Инвариант | Почему важен | Где реализован | Safe path |
| --- | --- | --- | --- |
| `UNKNOWN` | `UNKNOWN` | `UNKNOWN` | `UNKNOWN` |

## Внешние контракты

- Публичные API/protocols: `UNKNOWN`
- Events/queues/webhooks: `UNKNOWN`
- Database/schema compatibility: `UNKNOWN`
- Consumers, которые нельзя обнаружить только по коду: `UNKNOWN`

## Состояние, данные и транзакции

- Источники истины: `UNKNOWN`
- Границы транзакций и идемпотентность: `UNKNOWN`
- Consistency/retry/deduplication правила: `UNKNOWN`
- Retention/PII/secrets требования: `UNKNOWN`

## Наблюдаемость и эксплуатация

- Ключевые логи и correlation IDs: `UNKNOWN`
- Метрики/SLO/alerts: `UNKNOWN`
- Health/readiness checks: `UNKNOWN`
- Feature flags и rollback mechanism: `UNKNOWN`
- Runbooks: `UNKNOWN`

## Чувствительные области

Перечисли auth, billing, permissions, migrations, concurrency, production
configuration и другие области, где требуется высокий риск-класс.

- `UNKNOWN`

## Generated и vendored content

- Пути: `UNKNOWN`
- Команда генерации: `UNKNOWN`
- Что проверять вместо построчного review: `UNKNOWN`

## Известные ограничения и исторические решения

- `UNKNOWN`

## Project-specific overrides

- Slice budget: использовать `.agent-flow/config.env`.
- Дополнительные approval gates: `NONE`
- Запрещённые изменения: `NONE`
- Обязательные проверки: `UNKNOWN`

