# Prompt: Bootstrap проекта

Прочитай корневой `AGENTS.md`, `.agent-flow/POLICY.md` и текущий
`.agent-flow/PROJECT.md`.

Работай в read-only режиме относительно production-кода. Разрешено менять только
`.agent-flow/PROJECT.md`.

1. Информационной командой проверь, исключены ли `AGENTS.md` и `.agent-flow/`
   локальными Git rules. Если нет, попроси человека выполнить
   `.agent-flow/bin/flow setup-local`; сам эту команду не запускай.
2. Определи реальные языки, framework, package/build tools и repo layout.
3. Найди entry points, модули, storage, integrations и deployment artifacts.
4. Найди CI-команды, test suites, lint/type/build/quality/security checks.
5. Найди существующие repository instructions и architecture docs.
6. Построй основной request/event/data flow со ссылками на пути и symbols.
7. Выведи доменные/технические инварианты только из evidence; неизвестное пометь
   `UNKNOWN` и сформулируй вопрос человеку.
8. Найди compatibility surfaces, sensitive areas, generated paths,
   observability и rollback mechanisms.
9. Безопасно запусти быстрые команды проверки, если окружение готово. Не
   устанавливай зависимости и не меняй систему без разрешения.
10. Заполни `PROJECT.md` компактно и по-русски. Не копируй большие куски README
    или кода.
11. Покажи человеку:
    - архитектурную карту;
    - пять наиболее важных инвариантов;
    - проверенные и непроверенные команды;
    - неизвестные доменные решения;
    - чувствительные зоны.

Остановись. Не ставь `HUMAN_APPROVED` самостоятельно и не начинай фичу.
